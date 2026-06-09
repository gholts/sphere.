import Foundation

@MainActor
extension AppModel {
    func updateConnections(_ snapshot: ConnectionsSnapshot) {
        if connections != snapshot {
            connections = snapshot
        }
        let count = snapshot.connections.count
        if overview.activeConnections != count {
            overview.activeConnections = count
            scheduleCacheSave()
        }
    }

    func updateMemory(_ memoryBytes: Int) {
        guard overview.memoryBytes != memoryBytes else { return }
        overview.memoryBytes = memoryBytes
        scheduleCacheSave()
    }

    func updateTraffic(upload: Int, download: Int) {
        guard overview.uploadBytesPerSecond != upload || overview.downloadBytesPerSecond != download
        else { return }
        overview.uploadBytesPerSecond = upload
        overview.downloadBytesPerSecond = download
        scheduleCacheSave()
    }

    func resetLoadedData() {
        pendingBackendErrorMessage = nil
        pendingCacheSave = false
        isBackendErrorDebouncing = false
        isManualRefreshActive = false
        toolbarRefreshingTabs.removeAll()
        manualRefreshDepth = 0
        loadedCacheProfileID = nil
        errorMessage = nil
        backendSuccessGeneration &+= 1
        backendErrorDebounceRevision &+= 1
        cacheSaveRevision &+= 1
        liveState.reset()
        proxyStore.reset()
        configStore.reset()
    }

    func proxyGroupExpandedKey(_ groupName: String) -> String {
        proxyStore.proxyGroupExpandedKey(groupName, profileID: selectedProfileID)
    }

    @discardableResult
    func setProxyCollection(_ collection: ProxyCollection) -> Bool {
        proxyStore.setProxyCollection(collection, profileID: selectedProfileID)
    }

    @discardableResult
    func setProxyProviders(_ providers: [ProxyProvider]) -> Bool {
        proxyStore.setProxyProviders(providers)
    }

    func proxyItem(named name: String) -> ProxyItem? {
        proxyStore.proxyItem(named: name)
    }

    func rebuildProxyLookup() {
        proxyStore.rebuildProxyLookup()
    }

    func applyOverviewStats(_ nextOverview: BackendOverview) {
        var didChange = false
        if let uptime = nextOverview.uptime, overview.uptime != uptime {
            overview.uptime = uptime
            didChange = true
        }
        if let memoryBytes = nextOverview.memoryBytes, overview.memoryBytes != memoryBytes {
            overview.memoryBytes = memoryBytes
            didChange = true
        }
        if let uploadBytesPerSecond = nextOverview.uploadBytesPerSecond,
            overview.uploadBytesPerSecond != uploadBytesPerSecond {
            overview.uploadBytesPerSecond = uploadBytesPerSecond
            didChange = true
        }
        if let downloadBytesPerSecond = nextOverview.downloadBytesPerSecond,
            overview.downloadBytesPerSecond != downloadBytesPerSecond {
            overview.downloadBytesPerSecond = downloadBytesPerSecond
            didChange = true
        }
        if let activeConnections = nextOverview.activeConnections,
            overview.activeConnections != activeConnections {
            overview.activeConnections = activeConnections
            didChange = true
        }
        if didChange {
            scheduleCacheSave()
        }
    }

    func applyVersion(_ version: String) {
        guard version != overview.version else { return }
        overview.version = version
    }

    func applyConfigs(_ values: [String: JSONValue]) {
        configStore.applyConfigs(values)
    }
}
