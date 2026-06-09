import Foundation

private enum SurgeOverviewValue: Sendable {
    case traffic(Result<TrafficSnapshot, Error>)
    case connections(Result<ConnectionsSnapshot, Error>)
}

nonisolated struct SurgeClient: ProxyBackendClient {
    var profile: APIProfile { transport.profile }

    private let transport: BackendTransport

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
            profile: profile, session: session, requestTimeout: requestTimeout)
    }

    func testConnection() async throws -> BackendOverview {
        _ = try await events()
        var result = BackendOverview.empty
        result.version = version()
        return result
    }

    func version() -> String {
        "Surge HTTP API"
    }

    func overview() async -> BackendOverview {
        var traffic: TrafficSnapshot?
        var connections: ConnectionsSnapshot?

        await withTaskGroup(of: SurgeOverviewValue.self) { taskGroup in
            taskGroup.addTask { .traffic(await backendResult { try await self.traffic() }) }
            taskGroup.addTask { .connections(await backendResult { try await self.connections() }) }

            for await value in taskGroup {
                switch value {
                case .traffic(.success(let snapshot)):
                    traffic = snapshot
                case .connections(.success(let snapshot)):
                    connections = snapshot
                case .traffic(.failure), .connections(.failure):
                    break
                }
            }
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

    func configs() async throws -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        let outbound = try await outbound()
        values.mergeJSONPatch(["outbound": .object(["mode": .string(outbound.mode)])])

        if let global = try? await globalPolicy(), !global.policy.isEmpty {
            values.mergeJSONPatch(["outbound": .object(["global_policy": .string(global.policy)])])
        }

        var features: [String: JSONValue] = [:]
        for feature in SurgeFeature.allCases {
            if let payload = try? await featureState(feature) {
                features[feature.configKey] = .bool(payload.enabled)
            }
        }
        if !features.isEmpty {
            values["features"] = .object(features)
        }

        if let modules = try? await modules() {
            let enabled = Set(modules.enabled)
            let moduleValues = Dictionary(
                uniqueKeysWithValues: modules.available.map { ($0, JSONValue.bool(enabled.contains($0))) }
            )
            if !moduleValues.isEmpty {
                values["modules"] = .object(moduleValues)
            }
        }

        return values
    }

    func patchConfigs(_ values: [String: JSONValue]) async throws {
        var didPatch = false
        if case .object(let outbound)? = values["outbound"] {
            if case .string(let mode)? = outbound["mode"] {
                try await updateOutboundMode(mode)
                didPatch = true
            }
            if case .string(let policy)? = outbound["global_policy"] {
                try await updateGlobalPolicy(policy)
                didPatch = true
            }
        }

        if case .object(let features)? = values["features"] {
            for feature in SurgeFeature.allCases {
                if case .bool(let enabled)? = features[feature.configKey] {
                    try await updateFeature(feature, enabled: enabled)
                    didPatch = true
                }
            }
        }

        if case .object(let modules)? = values["modules"] {
            let body = try JSONEncoder().encode(
                modules.compactMapValues { value -> Bool? in
                    if case .bool(let enabled) = value { return enabled }
                    return nil
                }
            )
            try await transport.requestNoBody(path: "/v1/modules", method: "POST", body: body)
            didPatch = true
        }

        guard didPatch else {
            throw BackendError.unsupportedBackend("Surge config patch")
        }
    }

    func reloadConfig() async throws {
        try await transport.requestNoBody(path: "/v1/profiles/reload", method: "POST")
    }

    func clashMode() async throws -> ClashMode {
        try await outbound().clashMode
    }

    func updateClashMode(_ mode: ClashMode) async throws {
        let surgeMode: String
        switch mode {
        case .direct:
            surgeMode = "direct"
        case .global:
            surgeMode = "proxy"
        case .rule:
            surgeMode = "rule"
        }
        try await updateOutboundMode(surgeMode)
    }

    func proxies() async throws -> ProxyCollection {
        let policies = try await transport.request(
            path: "/v1/policies", response: SurgePoliciesPayload.self
        ).names
        let groups = try await policyGroupsWithSelections()
        let groupNames = Set(groups.map(\.name))
        let nodeNames = (policies + groups.flatMap(\.all)).stableUniquePolicyNames
            .filter { !groupNames.contains($0) }
        return ProxyCollection(
            proxies: nodeNames.map { ProxyItem(name: $0, type: "Policy") },
            groups: groups
        )
    }

    func selectProxy(group: String, proxy: String) async throws {
        let body = try JSONEncoder().encode(["group_name": group, "policy": proxy])
        try await transport.requestNoBody(path: "/v1/policy_groups/select", method: "POST", body: body)
    }

    func delayProxy(
        _ proxy: String,
        url: String,
        timeout: Int
    ) async throws -> Int? {
        _ = proxy
        _ = url
        _ = timeout
        throw BackendError.unsupportedBackend("Surge latency")
    }

    func delayProxyGroup(
        _ group: String,
        url _: String,
        timeout _: Int
    ) async throws -> [String: Int] {
        _ = group
        throw BackendError.unsupportedBackend("Surge latency")
    }

    func refreshProxyGroup(_ group: String) async throws -> ProxyGroupRefreshReport {
        let data = try await transport.rawData(
            path: "/v1/profiles/reload",
            query: [],
            method: "POST",
            body: nil
        )
        return ProxyGroupRefreshReport(
            groupName: group,
            message: SurgeRefreshMessage.message(from: data)
                ?? "Profile reload requested. Surge returned no provider refresh detail."
        )
    }

    func proxyProviders() -> [ProxyProvider] {
        []
    }

    func refreshProxyProvider(_: String) {
        // Surge HTTP API has no proxy provider refresh endpoint.
    }

    func rules() async throws -> [RuleItem] {
        try await transport.request(path: "/v1/rules", response: SurgeRulesPayload.self).rules
    }

    func ruleProviders() -> [RuleProvider] {
        []
    }

    func refreshRuleProvider(_: String) {
        // Surge HTTP API has no rule provider refresh endpoint.
    }

    func connections() async throws -> ConnectionsSnapshot {
        let connections = try await transport.request(
            path: "/v1/requests/active",
            response: SurgeRequestsPayload.self
        ).connections
        return ConnectionsSnapshot(uploadTotal: nil, downloadTotal: nil, connections: connections)
    }

    func closeConnection(_ id: String) async throws {
        let numericID = Int(id) ?? 0
        let body = try JSONEncoder().encode(["id": numericID])
        try await transport.requestNoBody(path: "/v1/requests/kill", method: "POST", body: body)
    }

    func closeAllConnections() async throws {
        let snapshot = try await connections()
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for connection in snapshot.connections {
                taskGroup.addTask { try await closeConnection(connection.id) }
            }
            try await taskGroup.waitForAll()
        }
    }

    func upgradeCore(channel _: CoreUpdateChannel) throws {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }

    func logs(level: LogLevel) -> AsyncThrowingStream<LogEntry, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var seen: Set<String> = []
                do {
                    try await updateLogLevel(level)
                    while !Task.isCancelled {
                        for entry in try await events().logs {
                            guard level.allowsSurgeLog(entry.type) else { continue }
                            let key = "\(entry.type):\(entry.payload)"
                            if seen.insert(key).inserted {
                                continuation.yield(entry)
                            }
                        }
                        try await Task.sleep(for: .seconds(2))
                    }
                } catch where Task.isCancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func connectionEvents(interval: Int) -> AsyncThrowingStream<ConnectionsSnapshot, Error> {
        pollingStream(interval: .milliseconds(interval)) {
            try await connections()
        }
    }

    func memoryEvents() -> AsyncThrowingStream<MemorySnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: BackendError.unsupportedBackend("Surge memory stream"))
        }
    }

    func trafficEvents() -> AsyncThrowingStream<TrafficSnapshot, Error> {
        pollingStream(interval: .seconds(1)) {
            try await traffic()
        }
    }

    func setFeature(_ feature: SurgeFeature, enabled: Bool) async throws {
        try await updateFeature(feature, enabled: enabled)
    }

    func dnsCache() async throws -> [String: JSONValue] {
        try await transport.request(path: "/v1/dns", response: [String: JSONValue].self)
    }

    func flushDNS() async throws {
        try await transport.requestNoBody(path: "/v1/dns/flush", method: "POST")
    }

    func stopEngine() async throws {
        try await transport.requestNoBody(path: "/v1/stop", method: "POST")
    }

    func mitmCertificate() async throws -> Data {
        try await transport.rawData(path: "/v1/mitm/ca", query: [], method: "GET", body: nil)
    }

    private func outbound() async throws -> SurgeOutboundPayload {
        try await transport.request(path: "/v1/outbound", response: SurgeOutboundPayload.self)
    }

    private func globalPolicy() async throws -> SurgeGlobalPolicyPayload {
        try await transport.request(path: "/v1/outbound/global", response: SurgeGlobalPolicyPayload.self)
    }

    private func modules() async throws -> SurgeModulesPayload {
        try await transport.request(path: "/v1/modules", response: SurgeModulesPayload.self)
    }

    private func events() async throws -> SurgeEventsPayload {
        try await transport.request(path: "/v1/events", response: SurgeEventsPayload.self)
    }

    private func traffic() async throws -> TrafficSnapshot {
        try await transport.request(path: "/v1/traffic", response: SurgeTrafficPayload.self).snapshot
    }

    private func featureState(_ feature: SurgeFeature) async throws -> SurgeFeaturePayload {
        try await transport.request(
            path: "/v1/features/\(feature.rawValue)", response: SurgeFeaturePayload.self)
    }

    private func updateFeature(_ feature: SurgeFeature, enabled: Bool) async throws {
        let body = try JSONEncoder().encode(SurgeFeaturePayload(enabled: enabled))
        try await transport.requestNoBody(
            path: "/v1/features/\(feature.rawValue)", method: "POST", body: body)
    }

    private func updateOutboundMode(_ mode: String) async throws {
        let body = try JSONEncoder().encode(["mode": mode])
        try await transport.requestNoBody(path: "/v1/outbound", method: "POST", body: body)
    }

    private func updateGlobalPolicy(_ policy: String) async throws {
        let body = try JSONEncoder().encode(["policy": policy])
        try await transport.requestNoBody(path: "/v1/outbound/global", method: "POST", body: body)
    }

    private func updateLogLevel(_ level: LogLevel) async throws {
        let surgeLevel = level == .debug ? "verbose" : level.rawValue
        let body = try JSONEncoder().encode(["level": surgeLevel])
        try await transport.requestNoBody(path: "/v1/log/level", method: "POST", body: body)
    }

    private func policyGroupsWithSelections() async throws -> [ProxyItem] {
        let groups = try await transport.request(
            path: "/v1/policy_groups", response: SurgePolicyGroupsPayload.self
        ).groups
        var selectedGroups: [ProxyItem] = []
        selectedGroups.reserveCapacity(groups.count)
        for group in groups {
            var copy = group
            if copy.now == nil,
                let selection = try? await transport.request(
                    path: "/v1/policy_groups/select",
                    query: [URLQueryItem(name: "group_name", value: group.name)],
                    response: SurgePolicySelectionPayload.self
                ).policy {
                copy.now = selection
            }
            selectedGroups.append(copy)
        }
        return selectedGroups
    }

    private func pollingStream<T: Sendable>(
        interval: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        continuation.yield(try await operation())
                        try await Task.sleep(for: interval)
                    }
                } catch where Task.isCancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private enum AnySendableJSON: Encodable, Sendable {
    case string(String)
    case int(Int)
    case strings([String])

    init(_ value: String) {
        self = .string(value)
    }

    init(_ value: Int) {
        self = .int(value)
    }

    init(_ value: [String]) {
        self = .strings(value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .strings(let values):
            try container.encode(values)
        }
    }
}

private func backendResult<T: Sendable>(
    _ operation: @Sendable () async throws -> T
) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

private extension LogLevel {
    nonisolated func allowsSurgeLog(_ type: String) -> Bool {
        Self.severity(of: type) >= minimumSurgeSeverity
    }

    nonisolated var minimumSurgeSeverity: Int {
        switch self {
        case .debug:
            return 0
        case .info:
            return 1
        case .warning:
            return 2
        case .error:
            return 3
        }
    }

    nonisolated static func severity(of type: String) -> Int {
        switch type.lowercased() {
        case "debug", "verbose":
            return 0
        case "warning", "warn":
            return 2
        case "error", "fault", "critical":
            return 3
        default:
            return 1
        }
    }
}

private extension Array where Element == String {
    nonisolated var stableUniquePolicyNames: [String] {
        var seen: Set<String> = []
        return filter { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return false }
            seen.insert(trimmed)
            return true
        }
    }
}
