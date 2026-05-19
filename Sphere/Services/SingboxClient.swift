import Foundation

nonisolated struct SingboxClient: ProxyBackendClient {
    var profile: APIProfile { transport.profile }
    
    private let transport: BackendTransport
    
    init(
        profile: APIProfile,
        session: URLSession = BackendTransport.makeSession(),
        requestTimeout: TimeInterval = BackendTransport.defaultRequestTimeout
    ) {
        self.transport = BackendTransport(profile: profile, session: session, requestTimeout: requestTimeout)
    }
    
    func testConnection() async throws -> BackendOverview {
        var result = BackendOverview.empty
        result.version = try await version()
        return result
    }
    
    func overview() async -> BackendOverview {
        let snapshot = try? await connections()
        return BackendOverview(
            version: "Unknown",
            uptime: nil,
            memoryBytes: snapshot?.memory,
            uploadBytesPerSecond: nil,
            downloadBytesPerSecond: nil,
            activeConnections: snapshot?.connections.count
        )
    }
    
    func configs() async throws -> [String: JSONValue] {
        try await transport.request(path: "/configs", response: [String: JSONValue].self)
    }
    
    func patchConfigs(_ values: [String: JSONValue]) async throws {
        try await transport.requestNoBody(path: "/configs", method: "PATCH", body: JSONEncoder().encode(values))
    }
    
    func reloadConfig() async throws {
        let body = try JSONEncoder().encode(["path": "", "payload": ""])
        try await transport.requestNoBody(
            path: "/configs",
            query: [URLQueryItem(name: "reload", value: "true")],
            method: "PUT",
            body: body
        )
    }
    
    func clashMode() async throws -> ClashMode {
        try await transport.request(path: "/configs", response: MihomoModePayload.self).mode ?? .rule
    }
    
    func updateClashMode(_ mode: ClashMode) async throws {
        try await patchConfigs(["mode": .string(mode.rawValue)])
    }
    
    func proxies() async throws -> ProxyCollection {
        try await transport.request(path: "/proxies", response: ProxyCollection.self)
    }
    
    func selectProxy(group: String, proxy: String) async throws {
        let body = try JSONEncoder().encode(["name": proxy])
        try await transport.requestNoBody(path: "/proxies/\(transport.escaped(group))", method: "PUT", body: body)
    }
    
    func delayProxy(_ proxy: String, url: String = ProxyLatencyTestDefaults.url, timeout: Int = ProxyLatencyTestDefaults.timeout) async throws -> Int? {
        try await transport.request(
            path: "/proxies/\(transport.escaped(proxy))/delay",
            query: [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: String(timeout)),
            ],
            response: ProxyDelayPayload.self
        ).delay
    }
    
    func delayProxyGroup(_ group: String, url: String = ProxyLatencyTestDefaults.url, timeout: Int = ProxyLatencyTestDefaults.timeout) async throws -> [String: Int] {
        try await transport.request(
            path: "/group/\(transport.escaped(group))/delay",
            query: [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: String(timeout)),
            ],
            response: [String: Int].self
        )
    }
    
    func proxyProviders() async throws -> [ProxyProvider] {
        try await transport.request(
            path: "/providers/proxies",
            response: ProviderCollection<ProxyProvider>.self
        ).providers.visibleProxyProviders
    }
    
    func refreshProxyProvider(_ name: String) {
        _ = name
    }
    
    func rules() async throws -> [RuleItem] {
        try await transport.request(path: "/rules", response: RuleCollection.self).rules
    }
    
    func ruleProviders() async throws -> [RuleProvider] {
        try await transport.request(path: "/providers/rules", response: ProviderCollection<RuleProvider>.self).providers
    }
    
    func refreshRuleProvider(_ name: String) {
        _ = name
    }
    
    func connections() async throws -> ConnectionsSnapshot {
        try await transport.request(path: "/connections", response: ConnectionsSnapshot.self)
    }
    
    func closeConnection(_ id: String) async throws {
        try await transport.requestNoBody(path: "/connections/\(transport.escaped(id))", method: "DELETE")
    }
    
    func closeAllConnections() async throws {
        try await transport.requestNoBody(path: "/connections", method: "DELETE")
    }
    
    func upgradeCore(channel _: CoreUpdateChannel) throws {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    
    func logs(level: LogLevel) -> AsyncThrowingStream<LogEntry, Error> {
        transport.webSocketStream(
            path: "/logs",
            query: [URLQueryItem(name: "level", value: level.rawValue)],
            response: LogEntry.self,
            appendsSecretToken: true
        )
    }
    
    func connectionEvents(interval: Int) -> AsyncThrowingStream<ConnectionsSnapshot, Error> {
        transport.webSocketStream(
            path: "/connections",
            query: [URLQueryItem(name: "interval", value: String(interval))],
            response: ConnectionsSnapshot.self,
            appendsSecretToken: true
        )
    }
    
    func memoryEvents() -> AsyncThrowingStream<MemorySnapshot, Error> {
        transport.webSocketStream(path: "/memory", query: [], response: MemorySnapshot.self, appendsSecretToken: true)
    }
    
    func trafficEvents() -> AsyncThrowingStream<TrafficSnapshot, Error> {
        transport.webSocketStream(path: "/traffic", query: [], response: TrafficSnapshot.self, appendsSecretToken: true)
    }
    
    func version() async throws -> String {
        try await transport.request(path: "/version", response: MihomoVersionPayload.self).version
    }
}
