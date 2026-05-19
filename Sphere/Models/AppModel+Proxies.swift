import Foundation

@MainActor
extension AppModel {
    func selectProxy(group: String, proxy: String) async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.selectProxy(group: group, proxy: proxy)
            setProxyCollection(try await client.proxies())
            saveCachedDataIfUseful()
        }
    }
    
    func refreshProxyProvider(_ name: String) async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.refreshProxyProvider(name)
            proxyProviders = try await client.proxyProviders()
            saveCachedDataIfUseful()
        }
    }
    
    func testProxyGroupDelays() async {
        guard let client, !isTestingProxyGroupDelays else { return }
        let groupNames = proxyCollection.groups.map(\.name)
        guard !groupNames.isEmpty else { return }
        
        proxyStore.isTestingProxyGroupDelays = true
        defer { proxyStore.isTestingProxyGroupDelays = false }
        
        await progressActivityReporter.start(
            kind: .latencyTest,
            detail: "0/\(groupNames.count) groups",
            fraction: 0
        )
        
        let outcome = await captureErrors {
            var didChange = false
            let delays = try await delayProxyGroups(client: client, groupNames: groupNames) { completed, total in
                await self.progressActivityReporter.update(
                    kind: .latencyTest,
                    detail: "\(completed)/\(total) groups",
                    fraction: Double(completed) / Double(total) * ProgressActivityFractions.latencyGroupTestingWeight
                )
            }
            if !delays.isEmpty {
                didChange = setProxyCollection(proxyCollection.applyingDelayResults(delays)) || didChange
            }
            await progressActivityReporter.update(
                kind: .latencyTest,
                detail: "Refreshing nodes",
                fraction: ProgressActivityFractions.latencyRefreshing
            )
            let proxyRefresh = await result { try await client.proxies() }
            switch proxyRefresh {
            case .success(let collection):
                didChange = setProxyCollection(collection) || didChange
            case .failure(let error):
                if delays.isEmpty {
                    throw error
                }
            }
            if didChange {
                saveCachedDataIfUseful()
            }
        }
        
        if outcome.errorMessage == nil {
            await progressActivityReporter.finish(
                kind: .latencyTest,
                status: .succeeded,
                detail: "Latency test finished"
            )
        } else {
            await progressActivityReporter.finish(
                kind: .latencyTest,
                status: .failed,
                detail: "Latency test failed"
            )
        }
    }
    
    func isProxyGroupExpanded(_ groupName: String) -> Bool {
        proxyStore.isProxyGroupExpanded(groupName, profileID: selectedProfileID)
    }
    
    func areAllProxyGroupsExpanded(_ groups: [ProxyItem]) -> Bool {
        proxyStore.areAllProxyGroupsExpanded(groups, profileID: selectedProfileID)
    }
    
    func setProxyGroupExpanded(_ isExpanded: Bool, groupName: String) {
        proxyStore.setProxyGroupExpanded(isExpanded, groupName: groupName, profileID: selectedProfileID)
    }
    
    func setAllProxyGroupsExpanded(_ isExpanded: Bool, groups: [ProxyItem]) {
        proxyStore.setAllProxyGroupsExpanded(isExpanded, groups: groups, profileID: selectedProfileID)
    }
}
