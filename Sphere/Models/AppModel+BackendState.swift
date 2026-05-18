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
            startLiveStreams()
            startAutoRefresh()
        }
        if source.waitsForBackendErrorDebounce {
            await waitForBackendErrorDebounceIfNeeded()
        }
    }

    func suspendBackgroundRefresh() {
        isAutoRefreshSuspended = true
        stopAutoRefresh()
        stopLiveStreams()
    }

    func finishManualRefresh(source: RefreshSource) {
        guard source.isUserInitiated else { return }
        manualRefreshDepth = max(0, manualRefreshDepth - 1)
        if manualRefreshDepth == 0 {
            isManualRefreshActive = false
        }
    }

    func waitForBackendErrorDebounceIfNeeded() async {
        guard isBackendErrorDebouncing, let backendErrorTask else { return }
        await backendErrorTask.value
    }

    func markBackendConnected() {
        backendSuccessGeneration &+= 1
        guard isBackendErrorDebouncing || errorMessage != nil || backendErrorTask != nil || pendingBackendErrorMessage != nil else {
            return
        }
        backendErrorTask?.cancel()
        backendErrorTask = nil
        pendingBackendErrorMessage = nil
        isBackendErrorDebouncing = false
        errorMessage = nil
    }

    func beginBackendErrorDebounce(_ message: String) {
        pendingBackendErrorMessage = message
        guard !isBackendErrorDebouncing else { return }
        backendErrorTask?.cancel()
        errorMessage = nil
        isBackendErrorDebouncing = true
        let generation = backendSuccessGeneration
        let duration = backendErrorDebounceDuration
        backendErrorTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            self?.confirmBackendError(startedAtGeneration: generation)
        }
    }

    func confirmBackendError(startedAtGeneration generation: Int) {
        backendErrorTask = nil
        guard backendSuccessGeneration == generation else {
            pendingBackendErrorMessage = nil
            isBackendErrorDebouncing = false
            errorMessage = nil
            return
        }
        errorMessage = pendingBackendErrorMessage
        pendingBackendErrorMessage = nil
        isBackendErrorDebouncing = false
    }

    func resetLoadedData() {
        stopLiveStreams()
        stopAutoRefresh()
        backendErrorTask?.cancel()
        cacheSaveTask?.cancel()
        backendErrorTask = nil
        cacheSaveTask = nil
        pendingBackendErrorMessage = nil
        isBackendErrorDebouncing = false
        isManualRefreshActive = false
        toolbarRefreshingTabs.removeAll()
        manualRefreshDepth = 0
        errorMessage = nil
        backendSuccessGeneration &+= 1
        liveStore.reset()
        proxyCollection = ProxyCollection()
        rebuildProxyLookup()
        proxyGroupIcons = [:]
        loadedProxyGroupIconsKey = nil
        proxyProviders = []
        rules = []
        ruleProviders = []
        logStore.reset()
        configs = [:]
        clashMode = .rule
    }

    func proxyGroupExpandedKey(_ groupName: String) -> String {
        "\(Keys.proxyGroupExpandedPrefix).\(selectedProfileID?.uuidString ?? "none").\(groupName)"
    }

    func cacheKey(profileID: UUID?) -> String {
        "\(Keys.cachedDataPrefix).\(profileID?.uuidString ?? "none")"
    }

    func cacheKey() -> String {
        cacheKey(profileID: selectedProfileID)
    }

    func proxyGroupIconsKey() -> String {
        "\(Keys.proxyGroupIconsPrefix).\(selectedProfileID?.uuidString ?? "none")"
    }

    func loadCachedData() {
        guard let data = defaults.data(forKey: cacheKey()),
              let snapshot = try? JSONDecoder().decode(BackendDataCache.self, from: data)
        else { return }
        overview = snapshot.overview
        proxyCollection = restoringCachedProxyGroupIcons(in: snapshot.proxyCollection)
        rebuildProxyLookup()
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
        cacheSaveTask?.cancel()
        cacheSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            self?.saveCachedDataIfUseful()
        }
    }

    func flushPendingCacheSave() {
        guard cacheSaveTask != nil else { return }
        cacheSaveTask?.cancel()
        cacheSaveTask = nil
        saveCachedDataIfUseful()
    }

    @discardableResult
    func setProxyCollection(_ collection: ProxyCollection) -> Bool {
        let nextCollection = restoringCachedProxyGroupIcons(in: collection)
        guard proxyCollection != nextCollection else {
            return mergeProxyGroupIcons(from: nextCollection.groups)
        }
        proxyCollection = nextCollection
        rebuildProxyLookup()
        _ = mergeProxyGroupIcons(from: nextCollection.groups)
        return true
    }

    @discardableResult
    func setProxyProviders(_ providers: [ProxyProvider]) -> Bool {
        guard proxyProviders != providers else { return false }
        proxyProviders = providers
        return true
    }

    func proxyItem(named name: String) -> ProxyItem? {
        proxyLookup[name] ?? proxyCollection.item(named: name)
    }

    func rebuildProxyLookup() {
        let pairs = (proxyCollection.proxies + proxyCollection.groups).map { ($0.name, $0) }
        proxyLookup = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    func ensureProxyGroupIconsLoaded() {
        let key = proxyGroupIconsKey()
        guard loadedProxyGroupIconsKey != key else { return }
        loadedProxyGroupIconsKey = key
        guard let data = defaults.data(forKey: key),
              let icons = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            proxyGroupIcons = [:]
            return
        }
        proxyGroupIcons = icons
    }

    func restoringCachedProxyGroupIcons(in collection: ProxyCollection) -> ProxyCollection {
        ensureProxyGroupIconsLoaded()
        guard !proxyGroupIcons.isEmpty else { return collection }
        var next = collection
        var restoredIcon = false
        next.groups = collection.groups.map { group in
            guard group.icon?.isEmpty ?? true, let icon = proxyGroupIcons[group.name] else { return group }
            restoredIcon = true
            var copy = group
            copy.icon = icon
            return copy
        }
        return restoredIcon ? next : collection
    }

    func mergeProxyGroupIcons(from groups: [ProxyItem]) -> Bool {
        ensureProxyGroupIconsLoaded()
        var changed = false
        for group in groups {
            guard let icon = group.icon, !icon.isEmpty else { continue }
            if proxyGroupIcons[group.name] != icon {
                proxyGroupIcons[group.name] = icon
                changed = true
            }
        }
        guard changed else { return false }
        saveProxyGroupIcons()
        return true
    }

    func saveProxyGroupIcons() {
        guard let data = try? JSONEncoder().encode(proxyGroupIcons) else { return }
        defaults.set(data, forKey: proxyGroupIconsKey())
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
        configs = values
        if case .string(let mode)? = values["mode"],
           let decodedMode = ClashMode(mihomoValue: mode) {
            clashMode = decodedMode
        }
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
