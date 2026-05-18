import Foundation

@MainActor
extension AppModel {
    func updateConnections(_ snapshot: ConnectionsSnapshot) {
        var didChange = false
        if connections != snapshot {
            connections = snapshot
            didChange = true
        }
        let count = snapshot.connections.count
        if overview.activeConnections != count {
            overview.activeConnections = count
            didChange = true
        }
        if didChange {
            scheduleCacheSave()
        }
    }

    func updateMemory(_ memoryBytes: Int) {
        guard overview.memoryBytes != memoryBytes else { return }
        overview.memoryBytes = memoryBytes
        scheduleCacheSave()
    }

    func updateTraffic(upload: Int, download: Int) {
        guard overview.uploadBytesPerSecond != upload || overview.downloadBytesPerSecond != download else { return }
        overview.uploadBytesPerSecond = upload
        overview.downloadBytesPerSecond = download
        scheduleCacheSave()
    }

    func result<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    func apply<T>(_ result: Result<T, Error>, onSuccess: (T) -> Void) -> RefreshOutcome {
        switch result {
        case .success(let value):
            onSuccess(value)
            var outcome = RefreshOutcome()
            outcome.markBackendConnected()
            return outcome
        case .failure(let error):
            return RefreshOutcome(error: error)
        }
    }

    func captureErrors(_ operation: () async throws -> Void) async -> RefreshOutcome {
        do {
            try await operation()
            markBackendConnected()
            var outcome = RefreshOutcome()
            outcome.markBackendConnected()
            return outcome
        } catch {
            guard !error.isCancellation else { return RefreshOutcome() }
            let outcome = RefreshOutcome(error: error)
            beginBackendErrorDebounce(error.localizedDescription)
            return outcome
        }
    }

    func delayProxyGroups(
        client: any ProxyBackendClient,
        groupNames: [String],
        progress: ((Int, Int) async -> Void)? = nil
    ) async throws -> [String: Int] {
        var mergedDelays: [String: Int] = [:]
        var firstError: Error?
        var successCount = 0
        var startIndex = groupNames.startIndex
        var completedCount = 0

        while startIndex < groupNames.endIndex {
            let endIndex = groupNames.index(startIndex, offsetBy: ProxyLatencyTestDefaults.maxConcurrentGroups, limitedBy: groupNames.endIndex) ?? groupNames.endIndex
            let batch = Array(groupNames[startIndex..<endIndex])
            let results = await withTaskGroup(of: Result<[String: Int], Error>.self) { taskGroup in
                for groupName in batch {
                    taskGroup.addTask {
                        do {
                            return .success(try await client.delayProxyGroup(
                                groupName,
                                url: ProxyLatencyTestDefaults.url,
                                timeout: ProxyLatencyTestDefaults.timeout
                            ))
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                var values: [Result<[String: Int], Error>] = []
                for await result in taskGroup {
                    values.append(result)
                }
                return values
            }

            for result in results {
                switch result {
                case .success(let delays):
                    successCount += 1
                    mergedDelays.merge(delays) { _, next in next }
                case .failure(let error):
                    firstError = firstError ?? error
                }
            }
            completedCount += batch.count
            await progress?(completedCount, groupNames.count)
            startIndex = endIndex
        }

        if successCount == 0, let firstError {
            throw firstError
        }
        return mergedDelays
    }

    func prepareRefresh(source: RefreshSource) {
        if source.isUserInitiated {
            manualRefreshDepth += 1
            isManualRefreshActive = true
            isAutoRefreshSuspended = false
        }
    }

    func finishRefresh(_ outcome: RefreshOutcome, source: RefreshSource) async {
        defer { finishManualRefresh(source: source) }
        if outcome.backendConnected {
            markBackendConnected()
        } else if let message = outcome.errorMessage {
            beginBackendErrorDebounce(message)
        }
        if outcome.connectionFailed {
            suspendBackgroundRefresh()
        } else if source.isUserInitiated {
            isAutoRefreshSuspended = false
        }
        if source.waitsForBackendErrorDebounce {
            await waitForBackendErrorDebounceIfNeeded()
        }
    }

    func suspendBackgroundRefresh() {
        isAutoRefreshSuspended = true
    }

    func finishManualRefresh(source: RefreshSource) {
        guard source.isUserInitiated else { return }
        manualRefreshDepth = max(0, manualRefreshDepth - 1)
        if manualRefreshDepth == 0 {
            isManualRefreshActive = false
        }
    }

    func waitForBackendErrorDebounceIfNeeded() async {
        await runBackendErrorDebounce(revision: backendErrorDebounceRevision)
    }

    func markBackendConnected() {
        backendSuccessGeneration &+= 1
        guard isBackendErrorDebouncing || errorMessage != nil || pendingBackendErrorMessage != nil else {
            return
        }
        pendingBackendErrorMessage = nil
        isBackendErrorDebouncing = false
        errorMessage = nil
        backendErrorDebounceRevision &+= 1
    }

    func beginBackendErrorDebounce(_ message: String) {
        pendingBackendErrorMessage = message
        guard !isBackendErrorDebouncing else { return }
        errorMessage = nil
        isBackendErrorDebouncing = true
        backendErrorStartedAtGeneration = backendSuccessGeneration
        backendErrorDebounceRevision &+= 1
    }

    func runBackendErrorDebounce() async {
        await runBackendErrorDebounce(revision: backendErrorDebounceRevision)
    }

    private func runBackendErrorDebounce(revision: Int) async {
        guard isBackendErrorDebouncing, revision == backendErrorDebounceRevision else { return }
        do {
            try await Task.sleep(for: backendErrorDebounceDuration)
        } catch {
            return
        }
        guard revision == backendErrorDebounceRevision else { return }
        confirmBackendError(startedAtGeneration: backendErrorStartedAtGeneration)
    }

    func confirmBackendError(startedAtGeneration generation: Int) {
        guard backendSuccessGeneration == generation else {
            pendingBackendErrorMessage = nil
            isBackendErrorDebouncing = false
            errorMessage = nil
            backendErrorDebounceRevision &+= 1
            return
        }
        errorMessage = pendingBackendErrorMessage
        pendingBackendErrorMessage = nil
        isBackendErrorDebouncing = false
    }

    func resetLoadedData() {
        pendingBackendErrorMessage = nil
        pendingCacheSave = false
        isBackendErrorDebouncing = false
        isManualRefreshActive = false
        toolbarRefreshingTabs.removeAll()
        manualRefreshDepth = 0
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

    func cacheKey(profileID: UUID?) -> String {
        "\(AppStorageKeys.cachedDataPrefix).\(profileID?.uuidString ?? "none")"
    }

    func cacheKey() -> String {
        cacheKey(profileID: selectedProfileID)
    }

    func loadCachedData() {
        guard let data = defaults.data(forKey: cacheKey()),
              let snapshot = try? JSONDecoder().decode(BackendDataCache.self, from: data)
        else { return }
        overview = snapshot.overview
        setProxyCollection(snapshot.proxyCollection)
        proxyProviders = snapshot.proxyProviders
        rules = snapshot.rules
        ruleProviders = snapshot.ruleProviders
        connections = snapshot.connections
        configs = snapshot.configs
        clashMode = snapshot.clashMode
    }

    func saveCachedDataIfUseful() {
        guard hasCacheableData else { return }
        let snapshot = BackendDataCache(
            overview: overview,
            proxyCollection: proxyCollection,
            proxyProviders: proxyProviders,
            rules: rules,
            ruleProviders: ruleProviders,
            connections: connections,
            configs: configs,
            clashMode: clashMode
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: cacheKey())
            lastCacheSave = Date()
        }
    }

    func scheduleCacheSave() {
        guard hasCacheableData else { return }
        let delay = cacheSaveInterval - Date().timeIntervalSince(lastCacheSave)
        guard delay > 0 else {
            saveCachedDataIfUseful()
            return
        }
        pendingCacheSave = true
        cacheSaveRevision &+= 1
    }

    func runPendingCacheSave() async {
        guard pendingCacheSave else { return }
        let delay = max(0, cacheSaveInterval - Date().timeIntervalSince(lastCacheSave))
        if delay > 0 {
            do {
                try await Task.sleep(for: .nanoseconds(Int64(delay * 1_000_000_000)))
            } catch {
                return
            }
        }
        guard pendingCacheSave else { return }
        pendingCacheSave = false
        saveCachedDataIfUseful()
    }

    func flushPendingCacheSave() {
        guard pendingCacheSave else { return }
        pendingCacheSave = false
        cacheSaveRevision &+= 1
        saveCachedDataIfUseful()
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
        if let uploadBytesPerSecond = nextOverview.uploadBytesPerSecond, overview.uploadBytesPerSecond != uploadBytesPerSecond {
            overview.uploadBytesPerSecond = uploadBytesPerSecond
            didChange = true
        }
        if let downloadBytesPerSecond = nextOverview.downloadBytesPerSecond, overview.downloadBytesPerSecond != downloadBytesPerSecond {
            overview.downloadBytesPerSecond = downloadBytesPerSecond
            didChange = true
        }
        if let activeConnections = nextOverview.activeConnections, overview.activeConnections != activeConnections {
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

    var hasCacheableData: Bool {
        overview != .empty ||
            !proxyCollection.proxies.isEmpty ||
            !proxyCollection.groups.isEmpty ||
            !proxyProviders.isEmpty ||
            !rules.isEmpty ||
            !ruleProviders.isEmpty ||
            !connections.connections.isEmpty ||
            !configs.isEmpty
    }
}

private struct BackendDataCache: Codable {
    var overview: BackendOverview
    var proxyCollection: ProxyCollection
    var proxyProviders: [ProxyProvider]
    var rules: [RuleItem]
    var ruleProviders: [RuleProvider]
    var connections: ConnectionsSnapshot
    var configs: [String: JSONValue]
    var clashMode: ClashMode
}
