import Foundation

extension SurgeClient {
    func proxies() async throws -> ProxyCollection {
        let policies = try await api.get(
            .policies,
            query: [],
            as: SurgePoliciesPayload.self
        ).names
        let groups = try await policyGroupsWithSelections()
        let groupNames = Set(groups.map(\.name))
        let nodeNames = (policies + groups.flatMap(\.all)).surgeStableUniqueNames
            .filter { !groupNames.contains($0) }
        return ProxyCollection(
            proxies: nodeNames.map { ProxyItem(name: $0, type: "Policy") },
            groups: groups
        )
    }

    func selectProxy(group: String, proxy: String) async throws {
        try await api.post(
            .policyGroupSelection,
            body: SurgePolicySelectionRequest(groupName: group, policy: proxy)
        )
    }

    func delayProxy(
        _ proxy: String,
        url: String,
        timeout: Int
    ) async throws -> Int? {
        let payload: SurgePolicyTestPayload = try await latencyAPI(timeout: timeout).post(
            .policiesTest,
            body: SurgePoliciesTestRequest(policyNames: [proxy], url: url),
            as: SurgePolicyTestPayload.self
        )
        return payload.delays[proxy] ?? payload.delays.values.first
    }

    func delayProxyGroup(
        _ group: String,
        url _: String,
        timeout: Int
    ) async throws -> [String: Int] {
        let payload: SurgePolicyTestPayload = try await latencyAPI(timeout: timeout).post(
            .policyGroupTest,
            body: SurgePolicyGroupTestRequest(groupName: group),
            as: SurgePolicyTestPayload.self
        )
        return payload.delays
    }

    func refreshProxyGroup(_ group: String) async throws -> ProxyGroupRefreshReport {
        let data = try await api.postData(.profilesReload)
        return ProxyGroupRefreshReport(
            groupName: group,
            message: SurgeRefreshMessage.message(from: data)
                ?? "Policy group refresh requested."
        )
    }

    func proxyProviders() -> [ProxyProvider] {
        []
    }

    func refreshProxyProvider(_: String) {
        // Surge HTTP API has no proxy provider refresh endpoint.
    }

    private func policyGroupsWithSelections() async throws -> [ProxyItem] {
        let groups = try await api.get(
            .policyGroups,
            query: [],
            as: SurgePolicyGroupsPayload.self
        ).groups
        return try await withThrowingTaskGroup(of: (Int, ProxyItem).self) { taskGroup in
            var iterator = groups.enumerated().makeIterator()
            for _ in 0..<min(4, groups.count) {
                guard let (index, group) = iterator.next() else { break }
                taskGroup.addTask {
                    try await resolvedSelection(for: group, at: index)
                }
            }

            var selectedGroups = Array(
                repeating: ProxyItem(name: "", type: ""),
                count: groups.count
            )
            while let (index, group) = try await taskGroup.next() {
                selectedGroups[index] = group
                if let (nextIndex, nextGroup) = iterator.next() {
                    taskGroup.addTask {
                        try await resolvedSelection(for: nextGroup, at: nextIndex)
                    }
                }
            }
            return selectedGroups
        }
    }

    private func resolvedSelection(
        for group: ProxyItem,
        at index: Int
    ) async throws -> (Int, ProxyItem) {
        guard group.now == nil else {
            return (index, group)
        }

        var selectedGroup = group
        do {
            selectedGroup.now = try await api.get(
                .policyGroupSelection,
                query: [URLQueryItem(name: "group_name", value: group.name)],
                as: SurgePolicySelectionPayload.self
            ).policy
        } catch where error.isCancellation || Task.isCancelled {
            throw CancellationError()
        } catch {
            // A missing selection must not discard an otherwise valid group.
        }
        return (index, selectedGroup)
    }

    private func latencyAPI(timeout: Int) -> SurgeAPI {
        var latencyTransport = transport
        latencyTransport.requestTimeout = max(30, TimeInterval(timeout) / 1000)
        return SurgeAPI(transport: latencyTransport)
    }
}

nonisolated private struct SurgePolicySelectionRequest: Encodable, Sendable {
    var groupName: String
    var policy: String

    enum CodingKeys: String, CodingKey {
        case groupName = "group_name"
        case policy
    }
}

nonisolated private struct SurgePoliciesTestRequest: Encodable, Sendable {
    var policyNames: [String]
    var url: String

    enum CodingKeys: String, CodingKey {
        case policyNames = "policy_names"
        case url
    }
}

nonisolated private struct SurgePolicyGroupTestRequest: Encodable, Sendable {
    var groupName: String

    enum CodingKeys: String, CodingKey {
        case groupName = "group_name"
    }
}
