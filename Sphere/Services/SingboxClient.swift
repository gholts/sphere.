import Foundation

nonisolated struct SingboxClient: ProxyBackendClient {
    var profile: APIProfile

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let requestTimeout: TimeInterval

    init(profile: APIProfile, session: URLSession = Self.makeSession(), requestTimeout: TimeInterval = 8) {
        self.profile = profile
        self.session = session
        self.requestTimeout = requestTimeout
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
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
        try await request(path: "/configs", response: [String: JSONValue].self)
    }

    func patchConfigs(_ values: [String: JSONValue]) async throws {
        try await requestNoBody(path: "/configs", method: "PATCH", body: encoder.encode(values))
    }

    func reloadConfig() async throws {
        let body = try encoder.encode(["path": "", "payload": ""])
        try await requestNoBody(path: "/configs", query: [URLQueryItem(name: "reload", value: "true")], method: "PUT", body: body)
    }

    func clashMode() async throws -> ClashMode {
        try await request(path: "/configs", response: MihomoModePayload.self).mode ?? .rule
    }

    func updateClashMode(_ mode: ClashMode) async throws {
        try await patchConfigs(["mode": .string(mode.rawValue)])
    }

    func proxies() async throws -> ProxyCollection {
        try await request(path: "/proxies", response: ProxyCollection.self)
    }

    func selectProxy(group: String, proxy: String) async throws {
        let body = try encoder.encode(["name": proxy])
        try await requestNoBody(path: "/proxies/\(escaped(group))", method: "PUT", body: body)
    }

    func delayProxy(_ proxy: String, url: String = ProxyLatencyTestDefaults.url, timeout: Int = ProxyLatencyTestDefaults.timeout) async throws -> Int? {
        try await request(
            path: "/proxies/\(escaped(proxy))/delay",
            query: [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: String(timeout)),
            ],
            response: ProxyDelayPayload.self
        ).delay
    }

    func delayProxyGroup(_ group: String, url: String = ProxyLatencyTestDefaults.url, timeout: Int = ProxyLatencyTestDefaults.timeout) async throws -> [String: Int] {
        try await request(
            path: "/group/\(escaped(group))/delay",
            query: [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "timeout", value: String(timeout)),
            ],
            response: [String: Int].self
        )
    }

    func proxyProviders() async throws -> [ProxyProvider] {
        try await request(path: "/providers/proxies", response: ProviderCollection<ProxyProvider>.self).providers.visibleProxyProviders
    }

    func refreshProxyProvider(_ name: String) {
        _ = name
    }

    func rules() async throws -> [RuleItem] {
        try await request(path: "/rules", response: RuleCollection.self).rules
    }

    func ruleProviders() async throws -> [RuleProvider] {
        try await request(path: "/providers/rules", response: ProviderCollection<RuleProvider>.self).providers
    }

    func refreshRuleProvider(_ name: String) {
        _ = name
    }

    func connections() async throws -> ConnectionsSnapshot {
        try await request(path: "/connections", response: ConnectionsSnapshot.self)
    }

    func closeConnection(_ id: String) async throws {
        try await requestNoBody(path: "/connections/\(escaped(id))", method: "DELETE")
    }

    func closeAllConnections() async throws {
        try await requestNoBody(path: "/connections", method: "DELETE")
    }

    func upgradeCore(channel _: CoreUpdateChannel) throws {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }

    func logs(level: LogLevel) -> AsyncThrowingStream<LogEntry, Error> {
        webSocketStream(path: "/logs", query: [URLQueryItem(name: "level", value: level.rawValue)], response: LogEntry.self)
    }

    func connectionEvents(interval: Int) -> AsyncThrowingStream<ConnectionsSnapshot, Error> {
        webSocketStream(path: "/connections", query: [URLQueryItem(name: "interval", value: String(interval))], response: ConnectionsSnapshot.self)
    }

    func memoryEvents() -> AsyncThrowingStream<MemorySnapshot, Error> {
        webSocketStream(path: "/memory", query: [], response: MemorySnapshot.self)
    }

    func trafficEvents() -> AsyncThrowingStream<TrafficSnapshot, Error> {
        webSocketStream(path: "/traffic", query: [], response: TrafficSnapshot.self)
    }

    func version() async throws -> String {
        try await request(path: "/version", response: MihomoVersionPayload.self).version
    }

    private func request<T: Decodable>(path: String, query: [URLQueryItem] = [], response _: T.Type) async throws -> T {
        let request = try URLRequestFactory.request(profile: profile, path: path, query: query, timeoutInterval: requestTimeout)
        let data = try await data(for: request)
        return try decoder.decode(T.self, from: data)
    }

    private func requestNoBody(path: String, query: [URLQueryItem] = [], method: String, body: Data? = nil) async throws {
        let request = try URLRequestFactory.request(profile: profile, path: path, query: query, method: method, body: body, timeoutInterval: requestTimeout)
        _ = try await data(for: request)
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data.isEmpty ? Data("{}".utf8) : data
    }

    private func webSocketStream<T: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem],
        response: T.Type
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            do {
                let request = try webSocketRequest(path: path, query: query)
                let task = session.webSocketTask(with: request)
                task.resume()
                let streamTask = Task {
                    do {
                        while !Task.isCancelled {
                            let message = try await task.receive()
                            let data: Data
                            switch message {
                            case .data(let value):
                                data = value
                            case .string(let value):
                                data = Data(value.utf8)
                            @unknown default:
                                continue
                            }
                            continuation.yield(try JSONDecoder().decode(response, from: data))
                        }
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    streamTask.cancel()
                    task.cancel(with: .goingAway, reason: nil)
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private func webSocketRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        var webSocketQuery = query
        if !profile.secret.isEmpty {
            webSocketQuery.append(URLQueryItem(name: "token", value: profile.secret))
        }
        var request = try URLRequestFactory.request(profile: profile, path: path, query: webSocketQuery, timeoutInterval: requestTimeout)
        guard let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw BackendError.invalidBaseURL
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let webSocketURL = components.url else {
            throw BackendError.invalidBaseURL
        }
        request.url = webSocketURL
        return request
    }

    private func escaped(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/%?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
