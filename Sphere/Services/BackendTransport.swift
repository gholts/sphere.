import Foundation

nonisolated struct BackendTransport: Sendable {
    static let defaultRequestTimeout: TimeInterval = 8
    static let defaultResourceTimeout: TimeInterval = 20

    var profile: APIProfile
    var session: URLSession
    var requestTimeout: TimeInterval

    init(
        profile: APIProfile,
        session: URLSession = Self.makeSession(),
        requestTimeout: TimeInterval = Self.defaultRequestTimeout
    ) {
        self.profile = profile
        self.session = session
        self.requestTimeout = requestTimeout
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = defaultRequestTimeout
        configuration.timeoutIntervalForResource = defaultResourceTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    func request<T: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        response _: T.Type
    ) async throws -> T {
        let request = try URLRequestFactory.request(
            profile: profile,
            path: path,
            query: query,
            timeoutInterval: requestTimeout
        )
        let data = try await data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func requestNoBody(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: Data? = nil
    ) async throws {
        let request = try URLRequestFactory.request(
            profile: profile,
            path: path,
            query: query,
            method: method,
            body: body,
            timeoutInterval: requestTimeout
        )
        _ = try await data(for: request)
    }

    func webSocketStream<T: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem],
        response: T.Type,
        appendsSecretToken: Bool = false
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            do {
                let request = try webSocketRequest(
                    path: path,
                    query: query,
                    appendsSecretToken: appendsSecretToken
                )
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

    func escaped(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/%?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.httpStatus(
                http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data.isEmpty ? Data("{}".utf8) : data
    }

    private func webSocketRequest(
        path: String,
        query: [URLQueryItem],
        appendsSecretToken: Bool
    ) throws -> URLRequest {
        var webSocketQuery = query
        if appendsSecretToken, !profile.secret.isEmpty {
            webSocketQuery.append(URLQueryItem(name: "token", value: profile.secret))
        }
        var request = try URLRequestFactory.request(
            profile: profile,
            path: path,
            query: webSocketQuery,
            timeoutInterval: requestTimeout
        )
        guard let url = request.url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw BackendError.invalidBaseURL
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let webSocketURL = components.url else {
            throw BackendError.invalidBaseURL
        }
        request.url = webSocketURL
        return request
    }
}
