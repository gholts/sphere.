import Foundation

private enum RefreshAllValue: Sendable {
    case version(Result<String, Error>)
    case overview(Result<BackendOverview, Error>)
    case proxies(Result<ProxyCollection, Error>)
    case proxyProviders(Result<[ProxyProvider], Error>)
    case rules(Result<[RuleItem], Error>)
    case ruleProviders(Result<[RuleProvider], Error>)
    case configs(Result<[String: JSONValue], Error>)
    case mode(Result<ClashMode, Error>)
}

private enum RefreshProxiesValue: Sendable {
    case proxies(Result<ProxyCollection, Error>)
    case proxyProviders(Result<[ProxyProvider], Error>)
}

private enum RefreshRulesValue: Sendable {
    case rules(Result<[RuleItem], Error>)
    case ruleProviders(Result<[RuleProvider], Error>)
    case configs(Result<[String: JSONValue], Error>)
}

nonisolated private func backendResult<T: Sendable>(
    _ operation: @Sendable () async throws -> T
) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

@MainActor
extension AppModel {
    func refreshAll(source: RefreshSource = .manual) async {
        await loadCachedDataIfNeeded()
        guard let client else { return }
        prepareRefresh(source: source)
        isLoading = true
        defer { isLoading = false }
        
        var outcome = RefreshOutcome()
        await withTaskGroup(of: RefreshAllValue.self) { taskGroup in
            taskGroup.addTask { .version(await backendResult { try await client.version() }) }
            taskGroup.addTask { .overview(await backendResult { try await client.overview() }) }
            taskGroup.addTask { .proxies(await backendResult { try await client.proxies() }) }
            taskGroup.addTask { .proxyProviders(await backendResult { try await client.proxyProviders() }) }
            taskGroup.addTask { .rules(await backendResult { try await client.rules() }) }
            taskGroup.addTask { .ruleProviders(await backendResult { try await client.ruleProviders() }) }
            taskGroup.addTask { .configs(await backendResult { try await client.configs() }) }
            taskGroup.addTask { .mode(await backendResult { try await client.clashMode() }) }
            
            for await value in taskGroup {
                switch value {
                case .version(let result):
                    outcome.merge(apply(result) { applyVersion($0) })
                case .overview(let result):
                    outcome.merge(apply(result) { applyOverviewStats($0) })
                case .proxies(let result):
                    outcome.merge(apply(result) { setProxyCollection($0) })
                case .proxyProviders(let result):
                    outcome.merge(apply(result) { proxyProviders = $0 })
                case .rules(let result):
                    outcome.merge(apply(result) { rules = $0 })
                case .ruleProviders(let result):
                    outcome.merge(apply(result) { ruleProviders = $0 })
                case .configs(let result):
                    outcome.merge(apply(result) { applyConfigs($0) })
                case .mode(let result):
                    outcome.merge(apply(result) { clashMode = $0 })
                }
            }
        }
        saveCachedDataIfUseful()
        await finishRefresh(outcome, source: source)
    }
    
    func runAutoRefreshLoop() async {
        guard !isAutoRefreshSuspended else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, !isAutoRefreshSuspended else { return }
            await refreshSelectedTab(source: .automatic)
        }
    }
    
    func refreshSelectedTab(source: RefreshSource = .manual) async {
        await loadCachedDataIfNeeded()
        if source == .automatic, isAutoRefreshSuspended {
            return
        }
        await refresh(tab: selectedTab, source: source)
    }
    
    func refreshFromToolbar(_ tab: AppTab) async {
        await loadCachedDataIfNeeded()
        guard !toolbarRefreshingTabs.contains(tab) else { return }
        toolbarRefreshingTabs.insert(tab)
        defer { toolbarRefreshingTabs.remove(tab) }
        await refresh(tab: tab, source: .manual)
    }
    
    func isToolbarRefreshing(_ tab: AppTab) -> Bool {
        toolbarRefreshingTabs.contains(tab)
    }
    
    private func refresh(tab: AppTab, source: RefreshSource) async {
        switch tab {
        case .proxies:
            await refreshProxies(source: source)
        case .rule:
            await refreshRules(source: source)
        case .connections:
            await refreshConnections(source: source)
        case .more:
            await refreshAll(source: source)
        }
    }
    
    func refreshProxies(source: RefreshSource = .manual) async {
        await loadCachedDataIfNeeded()
        guard let client else { return }
        prepareRefresh(source: source)
        
        var outcome = RefreshOutcome()
        var didChange = false
        
        await withTaskGroup(of: RefreshProxiesValue.self) { taskGroup in
            taskGroup.addTask { .proxies(await backendResult { try await client.proxies() }) }
            taskGroup.addTask { .proxyProviders(await backendResult { try await client.proxyProviders() }) }
            
            for await value in taskGroup {
                switch value {
                case .proxies(let result):
                    switch result {
                    case .success(let collection):
                        didChange = setProxyCollection(collection) || didChange
                        outcome.markBackendConnected()
                    case .failure(let error):
                        outcome.merge(RefreshOutcome(error: error))
                    }
                case .proxyProviders(let result):
                    switch result {
                    case .success(let providers):
                        didChange = setProxyProviders(providers) || didChange
                        outcome.markBackendConnected()
                    case .failure(let error):
                        outcome.merge(RefreshOutcome(error: error))
                    }
                }
            }
        }
        
        if didChange {
            saveCachedDataIfUseful()
        }
        await finishRefresh(outcome, source: source)
    }
    
    func refreshRules(source: RefreshSource = .manual) async {
        await loadCachedDataIfNeeded()
        guard let client else { return }
        prepareRefresh(source: source)
        
        var outcome = RefreshOutcome()
        await withTaskGroup(of: RefreshRulesValue.self) { taskGroup in
            taskGroup.addTask { .rules(await backendResult { try await client.rules() }) }
            taskGroup.addTask { .ruleProviders(await backendResult { try await client.ruleProviders() }) }
            taskGroup.addTask { .configs(await backendResult { try await client.configs() }) }
            
            for await value in taskGroup {
                switch value {
                case .rules(let result):
                    outcome.merge(apply(result) { rules = $0 })
                case .ruleProviders(let result):
                    outcome.merge(apply(result) { ruleProviders = $0 })
                case .configs(let result):
                    outcome.merge(apply(result) { applyConfigs($0) })
                }
            }
        }
        if outcome.backendConnected {
            saveCachedDataIfUseful()
        }
        await finishRefresh(outcome, source: source)
    }
}
