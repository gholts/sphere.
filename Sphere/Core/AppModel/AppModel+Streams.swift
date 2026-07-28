import Foundation

@MainActor
extension AppModel {
    func streamConnections() async {
        guard let client else { return }
        defer { flushPendingCacheSave() }
        do {
            for try await snapshot in client.connectionEvents(interval: 1000) {
                markBackendConnected()
                updateConnections(snapshot)
            }
        } catch where error.isCancellation || Task.isCancelled {
            return
        } catch {
            await pollBackend(every: .seconds(1)) {
                try await client.connections()
            } apply: {
                updateConnections($0)
            }
        }
    }

    func streamMemory() async {
        guard let client else { return }
        defer { flushPendingCacheSave() }
        do {
            for try await snapshot in client.memoryEvents() {
                markBackendConnected()
                if let inuse = snapshot.inuse {
                    updateMemory(inuse)
                }
            }
        } catch where error.isCancellation || Task.isCancelled {
            return
        } catch {
            await pollOverview(client: client)
        }
    }

    func streamTraffic() async {
        guard let client else { return }
        defer { flushPendingCacheSave() }
        do {
            for try await snapshot in client.trafficEvents() {
                markBackendConnected()
                updateTraffic(upload: snapshot.up, download: snapshot.down)
            }
        } catch where error.isCancellation || Task.isCancelled {
            return
        } catch {
            await pollOverview(client: client)
        }
    }

    func streamDevices() async {
        guard selectedProfile?.kind.supportsDeviceManagement == true, let client else {
            return
        }
        do {
            for try await devices in client.deviceEvents(interval: 2000) {
                markBackendConnected()
                updateDevices(devices)
            }
        } catch where error.isCancellation || Task.isCancelled {
            return
        } catch {
            beginBackendErrorDebounce(error.localizedDescription)
            if error.isConnectionFailure {
                suspendBackgroundRefresh()
            }
        }
    }

    func streamLogs(level: LogLevel) async {
        liveState.logs.removeAll()
        guard let client else { return }
        do {
            for try await entry in client.logs(level: level) {
                markBackendConnected()
                liveState.logs.append(entry)
                if liveState.logs.count > 400 {
                    liveState.logs.removeFirst(liveState.logs.count - 400)
                }
            }
        } catch where error.isCancellation || Task.isCancelled {
            return
        } catch {
            beginBackendErrorDebounce(error.localizedDescription)
        }
    }

    private func pollOverview(client: any ProxyBackendClient) async {
        await pollBackend(every: .seconds(1)) {
            try await client.overview()
        } apply: {
            applyOverviewStats($0)
        }
    }

    private func pollBackend<Value: Sendable>(
        every interval: Duration,
        operation: () async throws -> Value,
        apply: (Value) -> Void
    ) async {
        while !Task.isCancelled {
            do {
                apply(try await operation())
                markBackendConnected()
                try await Task.sleep(for: interval)
            } catch where error.isCancellation || Task.isCancelled {
                return
            } catch {
                beginBackendErrorDebounce(error.localizedDescription)
                if error.isConnectionFailure {
                    suspendBackgroundRefresh()
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
