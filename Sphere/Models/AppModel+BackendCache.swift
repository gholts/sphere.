import Foundation

@MainActor
extension AppModel {
    func cacheKey(profileID: UUID?) -> String {
        "\(AppStorageKeys.cachedDataPrefix).\(profileID?.uuidString ?? "none")"
    }

    func cacheKey() -> String {
        cacheKey(profileID: selectedProfileID)
    }

    func loadCachedDataIfNeeded() async {
        let profileID = selectedProfileID
        guard loadedCacheProfileID != profileID else { return }
        loadedCacheProfileID = profileID
        await loadCachedData(profileID: profileID)
    }

    private func loadCachedData(profileID: UUID?) async {
        guard let data = defaults.data(forKey: cacheKey(profileID: profileID)),
            let snapshot = await BackendCacheCodec.decode(data)
        else { return }
        guard selectedProfileID == profileID else { return }
        applyCachedData(snapshot)
    }

    private func applyCachedData(_ snapshot: BackendDataCache) {
        overview = snapshot.overview
        setProxyCollection(snapshot.proxyCollection)
        proxyProviders = snapshot.proxyProviders
        rules = snapshot.rules
        ruleProviders = snapshot.ruleProviders
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

    var hasCacheableData: Bool {
        overview != .empty || !proxyCollection.proxies.isEmpty || !proxyCollection.groups.isEmpty
            || !proxyProviders.isEmpty || !rules.isEmpty || !ruleProviders.isEmpty
            || !configs.isEmpty
    }
}

nonisolated private struct BackendDataCache: Codable, Sendable {
    var overview: BackendOverview
    var proxyCollection: ProxyCollection
    var proxyProviders: [ProxyProvider]
    var rules: [RuleItem]
    var ruleProviders: [RuleProvider]
    var configs: [String: JSONValue]
    var clashMode: ClashMode
}

nonisolated private enum BackendCacheCodec {
    @Sendable
    static func decode(_ data: Data) async -> BackendDataCache? {
        try? JSONDecoder().decode(BackendDataCache.self, from: data)
    }
}
