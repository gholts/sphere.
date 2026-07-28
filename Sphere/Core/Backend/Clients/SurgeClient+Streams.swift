import Foundation

extension SurgeClient {
    func logs(level: LogLevel) -> AsyncThrowingStream<LogEntry, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: LogEntry.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(400)
        )
        let task = Task {
            var seen: Set<String> = []
            var seenOrder: [String] = []
            do {
                try await updateLogLevel(level)
                while !Task.isCancelled {
                    for event in try await events().events {
                        guard level.allowsSurgeLog(event.entry.type) else {
                            continue
                        }
                        if seen.insert(event.identity).inserted {
                            seenOrder.append(event.identity)
                            continuation.yield(event.entry)
                        }
                    }
                    if seenOrder.count > 2000 {
                        let removalCount = seenOrder.count - 1500
                        for identity in seenOrder.prefix(removalCount) {
                            seen.remove(identity)
                        }
                        seenOrder.removeFirst(removalCount)
                    }
                    try await Task.sleep(for: .seconds(2))
                }
                continuation.finish()
            } catch where error.isCancellation || Task.isCancelled {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }

    func connectionEvents(interval: Int) -> AsyncThrowingStream<ConnectionsSnapshot, Error> {
        pollingStream(interval: .milliseconds(interval)) {
            try await connections()
        }
    }

    func memoryEvents() -> AsyncThrowingStream<MemorySnapshot, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: MemorySnapshot.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.finish()
        return stream
    }

    func trafficEvents() -> AsyncThrowingStream<TrafficSnapshot, Error> {
        pollingStream(interval: .seconds(1)) {
            try await traffic()
        }
    }

    func deviceEvents(interval: Int) -> AsyncThrowingStream<[SurgeDevice], Error> {
        pollingStream(interval: .milliseconds(max(interval, 100))) {
            do {
                return try await api.get(
                    .devices,
                    query: [],
                    as: SurgeDevicesPayload.self
                ).devices
            } catch BackendError.httpStatus(404, _) {
                return nil
            }
        }
    }

    private func events() async throws -> SurgeEventsPayload {
        try await api.get(.events, query: [], as: SurgeEventsPayload.self)
    }

    private func updateLogLevel(_ level: LogLevel) async throws {
        let surgeLevel = level == .debug ? "verbose" : level.rawValue
        try await api.post(
            .logLevel,
            body: SurgeLogLevelUpdate(level: surgeLevel)
        )
    }

    private func pollingStream<Value: Sendable>(
        interval: Duration,
        operation: @escaping @Sendable () async throws -> Value?
    ) -> AsyncThrowingStream<Value, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: Value.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let task = Task {
            do {
                while !Task.isCancelled {
                    guard let value = try await operation() else { break }
                    continuation.yield(value)
                    try await Task.sleep(for: interval)
                }
                continuation.finish()
            } catch where error.isCancellation || Task.isCancelled {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }
}

nonisolated private struct SurgeLogLevelUpdate: Encodable, Sendable {
    var level: String
}

private extension LogLevel {
    nonisolated func allowsSurgeLog(_ type: String) -> Bool {
        Self.severity(of: type) >= minimumSurgeSeverity
    }

    nonisolated var minimumSurgeSeverity: Int {
        switch self {
        case .debug:
            0
        case .info:
            1
        case .warning:
            2
        case .error:
            3
        }
    }

    nonisolated static func severity(of type: String) -> Int {
        switch type.lowercased() {
        case "debug", "verbose":
            0
        case "warning", "warn":
            2
        case "error", "fault", "critical":
            3
        default:
            1
        }
    }
}
