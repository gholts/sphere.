import Foundation

private enum SurgeOverviewValue: Sendable {
    case traffic(Result<TrafficSnapshot, Error>)
    case connections(Result<ConnectionsSnapshot, Error>)
}

nonisolated struct SurgeClient: ProxyBackendClient {
    let transport: BackendTransport

    var profile: APIProfile { transport.profile }
    var api: SurgeAPI { SurgeAPI(transport: transport) }

    init(profile: APIProfile) {
        self.init(
            profile: profile,
            session: BackendTransport.makeSession(acceptsUntrustedServerCertificates: true),
            requestTimeout: BackendTransport.defaultRequestTimeout
        )
    }

    init(
        profile: APIProfile,
        session: URLSession,
        requestTimeout: TimeInterval
    ) {
        self.transport = BackendTransport(
            profile: profile,
            session: session,
            requestTimeout: requestTimeout
        )
    }

    func testConnection() async throws -> BackendOverview {
        let headers = try await outboundHeaders()
        var result = BackendOverview.empty
        result.version = Self.versionDescription(headers: headers)
        return result
    }

    func version() async throws -> String {
        Self.versionDescription(headers: try await outboundHeaders())
    }

    func overview() async throws -> BackendOverview {
        var traffic: TrafficSnapshot?
        var connections: ConnectionsSnapshot?
        var failure: Error?

        await withTaskGroup(of: SurgeOverviewValue.self) { taskGroup in
            taskGroup.addTask {
                .traffic(await Self.result { try await self.traffic() })
            }
            taskGroup.addTask {
                .connections(await Self.result { try await self.connections() })
            }

            for await value in taskGroup {
                switch value {
                case .traffic(.success(let snapshot)):
                    traffic = snapshot
                case .connections(.success(let snapshot)):
                    connections = snapshot
                case .traffic(.failure(let error)), .connections(.failure(let error)):
                    failure = failure ?? error
                }
            }
        }
        try Task.checkCancellation()
        guard traffic != nil || connections != nil else {
            throw failure ?? BackendError.invalidResponse
        }

        return BackendOverview(
            version: "Unknown",
            uptime: nil,
            memoryBytes: nil,
            uploadBytesPerSecond: traffic?.up,
            downloadBytesPerSecond: traffic?.down,
            activeConnections: connections?.connections.count
        )
    }

    func upgradeCore(channel _: CoreUpdateChannel) throws {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }

    func outbound() async throws -> SurgeOutboundPayload {
        try await api.get(.outbound, query: [], as: SurgeOutboundPayload.self)
    }

    func traffic() async throws -> TrafficSnapshot {
        try await api.get(.traffic, query: [], as: SurgeTrafficPayload.self).snapshot
    }

    static func result<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async -> Result<Value, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func outboundHeaders() async throws -> [String: String] {
        try await api.getWithMetadata(
            .outbound,
            query: [],
            as: SurgeOutboundPayload.self
        )
    }

    private static func versionDescription(headers: [String: String]) -> String {
        guard
            let version = headers["x-surge-version"]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            !version.isEmpty
        else {
            return "Surge HTTP API"
        }

        if let build = headers["x-surge-build"]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !build.isEmpty {
            return "Surge \(version) (\(build))"
        }
        return "Surge \(version)"
    }
}
