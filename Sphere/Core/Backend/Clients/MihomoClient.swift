import Foundation

private enum MihomoOverviewValue: Sendable {
    case traffic(Result<TrafficSnapshot, Error>)
    case memory(Result<Int?, Error>)
    case connections(Result<ConnectionsSnapshot, Error>)
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

nonisolated struct MihomoClient: ProxyBackendClient {
    var profile: APIProfile { transport.profile }

    private let transport: BackendTransport

    init(
        profile: APIProfile,
        session: URLSession = BackendTransport.makeSession(),
        requestTimeout: TimeInterval = BackendTransport.defaultRequestTimeout
    ) {
        self.transport = BackendTransport(
            profile: profile, session: session, requestTimeout: requestTimeout)
    }

    func testConnection() async throws -> BackendOverview {
        var result = BackendOverview.empty
        result.version = try await version()
        return result
    }

    func overview() async -> BackendOverview {
        var traffic: TrafficSnapshot?
        var memory: Int?
        var connections: ConnectionsSnapshot?

        await withTaskGroup(of: MihomoOverviewValue.self) { taskGroup in
            taskGroup.addTask { .traffic(await backendResult { try await self.traffic() }) }
            taskGroup.addTask { .memory(await backendResult { try await self.memory() }) }
            taskGroup.addTask { .connections(await backendResult { try await self.connections() }) }

            for await value in taskGroup {
                switch value {
                case .traffic(.success(let snapshot)):
                    traffic = snapshot
                case .memory(.success(let inuse)):
                    memory = inuse
                case .connections(.success(let snapshot)):
                    connections = snapshot
                case .traffic(.failure), .memory(.failure), .connections(.failure):
                    break
                }
            }
        }

        return BackendOverview(
            version: "Unknown",
            uptime: nil,
            memoryBytes: memory,
            uploadBytesPerSecond: traffic?.up,
            downloadBytesPerSecond: traffic?.down,
            activeConnections: connections?.connections.count
        )
    }

    func configs() async throws -> [String: JSONValue] {
        try await transport.request(path: "/configs", response: [String: JSONValue].self)
    }

    func patchConfigs(_ values: [String: JSONValue]) async throws {
        try await transport.requestNoBody(
            path: "/configs", method: "PATCH", body: JSONEncoder().encode(values))
    }

    func reloadConfig() async throws {
        let body = try JSONEncoder().encode(["path": "", "payload": ""])
        try await transport.requestNoBody(
            path: "/configs",
            query: [URLQueryItem(name: "force", value: "true")],
            method: "PUT",
            body: body
        )
    }

    func clashMode() async throws -> ClashMode {
        try await transport.request(path: "/configs", response: MihomoModePayload.self).mode
            ?? .rule
    }

    func updateClashMode(_ mode: ClashMode) async throws {
        try await patchConfigs(["mode": .string(mode.mihomoValue)])
    }

    func proxies() async throws -> ProxyCollection {
        try await transport.request(path: "/proxies", response: ProxyCollection.self)
    }

    func selectProxy(group: String, proxy: String) async throws {
        let body = try JSONEncoder().encode(["name": proxy])
        try await transport.requestNoBody(
            path: "/proxies/\(transport.escaped(group))", method: "PUT", body: body)
    }

    func delayProxy(
        _ proxy: String,
        url: String = ProxyLatencyTestDefaults.url,
        timeout: Int = ProxyLatencyTestDefaults.timeout
    ) async throws -> Int? {
        try await transport.request(
            path: "/proxies/\(transport.escaped(proxy))/delay",
            query: [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: String(timeout)),
            ],
            response: ProxyDelayPayload.self
        ).delay
    }

    func delayProxyGroup(
        _ group: String,
        url: String = ProxyLatencyTestDefaults.url,
        timeout: Int = ProxyLatencyTestDefaults.timeout
    ) async throws -> [String: Int] {
        try await transport.request(
            path: "/group/\(transport.escaped(group))/delay",
            query: [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: String(timeout)),
            ],
            response: [String: Int].self
        )
    }

    func refreshProxyGroup(_: String) throws -> ProxyGroupRefreshReport {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }

    func proxyProviders() async throws -> [ProxyProvider] {
        try await transport.request(
            path: "/providers/proxies",
            response: ProviderCollection<ProxyProvider>.self
        ).providers.visibleProxyProviders
    }

    func refreshProxyProvider(_ name: String) async throws {
        try await transport.requestNoBody(
            path: "/providers/proxies/\(transport.escaped(name))", method: "PUT")
    }

    func rules() async throws -> [RuleItem] {
        try await transport.request(path: "/rules", response: RuleCollection.self).rules
    }

    func ruleProviders() async throws -> [RuleProvider] {
        try await transport.request(
            path: "/providers/rules", response: ProviderCollection<RuleProvider>.self
        ).providers
    }

    func refreshRuleProvider(_ name: String) async throws {
        try await transport.requestNoBody(
            path: "/providers/rules/\(transport.escaped(name))", method: "PUT")
    }

    func connections() async throws -> ConnectionsSnapshot {
        try await transport.request(path: "/connections", response: ConnectionsSnapshot.self)
    }

    func closeConnection(_ id: String) async throws {
        try await transport.requestNoBody(
            path: "/connections/\(transport.escaped(id))", method: "DELETE")
    }

    func closeAllConnections() async throws {
        try await transport.requestNoBody(path: "/connections", method: "DELETE")
    }

    func upgradeCore(channel: CoreUpdateChannel) async throws {
        try await transport.requestNoBody(
            path: "/upgrade",
            query: [URLQueryItem(name: "channel", value: channel.rawValue)],
            method: "POST"
        )
    }

    func logs(level: LogLevel) -> AsyncThrowingStream<LogEntry, Error> {
        transport.webSocketStream(
            path: "/logs", query: [URLQueryItem(name: "level", value: level.rawValue)],
            response: LogEntry.self)
    }

    func connectionEvents(interval: Int) -> AsyncThrowingStream<ConnectionsSnapshot, Error> {
        transport.webSocketStream(
            path: "/connections",
            query: [URLQueryItem(name: "interval", value: String(interval))],
            response: ConnectionsSnapshot.self
        )
    }

    func memoryEvents() -> AsyncThrowingStream<MemorySnapshot, Error> {
        transport.webSocketStream(path: "/memory", query: [], response: MemorySnapshot.self)
    }

    func trafficEvents() -> AsyncThrowingStream<TrafficSnapshot, Error> {
        transport.webSocketStream(path: "/traffic", query: [], response: TrafficSnapshot.self)
    }

    func version() async throws -> String {
        try await transport.request(path: "/version", response: MihomoVersionPayload.self).version
    }

    private func traffic() async throws -> TrafficSnapshot {
        try await transport.request(path: "/traffic", response: TrafficSnapshot.self)
    }

    private func memory() async throws -> Int? {
        try await transport.request(path: "/memory", response: MemorySnapshot.self).inuse
    }
}
