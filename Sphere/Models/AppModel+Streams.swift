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
            await pollConnections(client: client)
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
            await pollOverviewStats(client: client)
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
            await pollOverviewStats(client: client)
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
    
    private func pollConnections(client: any ProxyBackendClient) async {
        while !Task.isCancelled {
            do {
                updateConnections(try await client.connections())
                markBackendConnected()
                try await Task.sleep(for: .seconds(1))
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
    
    private func pollOverviewStats(client: any ProxyBackendClient) async {
        while !Task.isCancelled {
            do {
                applyOverviewStats(try await client.overview())
                markBackendConnected()
                try await Task.sleep(for: .seconds(1))
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
