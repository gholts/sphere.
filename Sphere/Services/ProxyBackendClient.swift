import Foundation

nonisolated protocol ProxyBackendClient: Sendable {
    var profile: APIProfile { get }

    func testConnection() async throws -> BackendOverview
    func version() async throws -> String
    func overview() async throws -> BackendOverview
    func configs() async throws -> [String: JSONValue]
    func patchConfigs(_ values: [String: JSONValue]) async throws
    func reloadConfig() async throws
    func clashMode() async throws -> ClashMode
    func updateClashMode(_ mode: ClashMode) async throws
    func proxies() async throws -> ProxyCollection
    func selectProxy(group: String, proxy: String) async throws
    func delayProxy(_ proxy: String, url: String, timeout: Int) async throws -> Int?
    func delayProxyGroup(_ group: String, url: String, timeout: Int) async throws -> [String: Int]
    func refreshProxyGroup(_ group: String) async throws -> ProxyGroupRefreshReport
    func proxyProviders() async throws -> [ProxyProvider]
    func refreshProxyProvider(_ name: String) async throws
    func rules() async throws -> [RuleItem]
    func ruleProviders() async throws -> [RuleProvider]
    func refreshRuleProvider(_ name: String) async throws
    func connections() async throws -> ConnectionsSnapshot
    func closeConnection(_ id: String) async throws
    func closeAllConnections() async throws
    func upgradeCore(channel: CoreUpdateChannel) async throws
    func logs(level: LogLevel) -> AsyncThrowingStream<LogEntry, Error>
    func connectionEvents(interval: Int) -> AsyncThrowingStream<ConnectionsSnapshot, Error>
    func memoryEvents() -> AsyncThrowingStream<MemorySnapshot, Error>
    func trafficEvents() -> AsyncThrowingStream<TrafficSnapshot, Error>
    func mitmCertificate() async throws -> Data
}

extension ProxyBackendClient {
    func mitmCertificate() async throws -> Data {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
}

nonisolated enum BackendClientFactory {
    static func make(profile: APIProfile) -> any ProxyBackendClient {
        switch profile.kind {
        case .mihomo:
            return MihomoClient(profile: profile)
        case .singbox:
            return SingboxClient(profile: profile)
        case .surge:
            return SurgeClient(profile: profile)
        }
    }
}

nonisolated struct UnsupportedBackendClient: ProxyBackendClient {
    var profile: APIProfile

    func testConnection() throws -> BackendOverview {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func version() throws -> String { throw BackendError.unsupportedBackend(profile.kind.title) }
    func overview() throws -> BackendOverview {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func configs() throws -> [String: JSONValue] {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func patchConfigs(_: [String: JSONValue]) throws {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func reloadConfig() throws { throw BackendError.unsupportedBackend(profile.kind.title) }
    func clashMode() throws -> ClashMode {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func updateClashMode(_: ClashMode) throws {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func proxies() throws -> ProxyCollection {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func selectProxy(group _: String, proxy _: String) throws {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func delayProxy(_: String, url _: String, timeout _: Int) throws -> Int? {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func delayProxyGroup(_: String, url _: String, timeout _: Int) throws -> [String: Int] {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func refreshProxyGroup(_: String) throws -> ProxyGroupRefreshReport {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func proxyProviders() throws -> [ProxyProvider] {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func refreshProxyProvider(_: String) throws {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func rules() throws -> [RuleItem] { throw BackendError.unsupportedBackend(profile.kind.title) }
    func ruleProviders() throws -> [RuleProvider] {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func refreshRuleProvider(_: String) throws {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func connections() throws -> ConnectionsSnapshot {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func closeConnection(_: String) throws {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func closeAllConnections() throws { throw BackendError.unsupportedBackend(profile.kind.title) }
    func upgradeCore(channel _: CoreUpdateChannel) throws {
        throw BackendError.unsupportedBackend(profile.kind.title)
    }
    func logs(level _: LogLevel) -> AsyncThrowingStream<LogEntry, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: BackendError.unsupportedBackend(profile.kind.title))
        }
    }
    func connectionEvents(interval _: Int) -> AsyncThrowingStream<ConnectionsSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: BackendError.unsupportedBackend(profile.kind.title))
        }
    }
    func memoryEvents() -> AsyncThrowingStream<MemorySnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: BackendError.unsupportedBackend(profile.kind.title))
        }
    }
    func trafficEvents() -> AsyncThrowingStream<TrafficSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: BackendError.unsupportedBackend(profile.kind.title))
        }
    }
}

nonisolated enum ProxyLatencyTestDefaults {
    nonisolated static let url = "https://www.gstatic.com/generate_204"
    nonisolated static let timeout = 5000
    nonisolated static let maxConcurrentGroups = 3
}

nonisolated enum BackendError: LocalizedError, Equatable, Sendable {
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int, String)
    case unsupportedBackend(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Bad backend URL"
        case .invalidResponse:
            return "Bad backend response"
        case let .httpStatus(status, body):
            return "HTTP \(status): \(HTTPErrorBodyDisplay.message(from: body))"
        case .unsupportedBackend(let backend):
            return "\(backend) backend not implemented"
        }
    }
}

nonisolated private enum HTTPErrorBodyDisplay {
    nonisolated private static let preferredKeys = [
        "message", "error", "detail", "reason", "description",
    ]

    nonisolated static func message(from body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return trimmed
        }

        return message(fromJSONObject: object) ?? trimmed
    }

    nonisolated private static func message(fromJSONObject object: Any) -> String? {
        if let text = object as? String {
            return text
        }
        if let number = object as? NSNumber {
            return number.stringValue
        }
        if let dictionary = object as? [String: Any] {
            for key in preferredKeys {
                if let value = dictionary[key], let message = message(fromJSONObject: value) {
                    return message
                }
            }
            if dictionary.count == 1, let value = dictionary.values.first {
                return message(fromJSONObject: value)
            }
        }
        return nil
    }
}

nonisolated struct URLRequestFactory {
    static func request(
        profile: APIProfile,
        path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        timeoutInterval: TimeInterval = 8
    ) throws -> URLRequest {
        guard
            var components = URLComponents(string: URLNormalizer.normalizedBaseURL(profile.baseURL))
        else {
            throw BackendError.invalidBaseURL
        }
        components.percentEncodedPath += path
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw BackendError.invalidBaseURL
        }
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutInterval)
        request.httpMethod = method
        if !profile.secret.isEmpty, profile.kind == .surge {
            request.setValue(profile.secret, forHTTPHeaderField: "X-Key")
        } else if !profile.secret.isEmpty {
            request.setValue("Bearer \(profile.secret)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
