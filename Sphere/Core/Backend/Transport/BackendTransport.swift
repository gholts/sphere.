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
        makeSession(acceptsUntrustedServerCertificates: false)
    }

    static func makeSession(acceptsUntrustedServerCertificates: Bool) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = defaultRequestTimeout
        configuration.timeoutIntervalForResource = defaultResourceTimeout
        configuration.waitsForConnectivity = false
        if acceptsUntrustedServerCertificates {
            return URLSession(
                configuration: configuration,
                delegate: BackendServerTrustDelegate(),
                delegateQueue: nil
            )
        }
        return URLSession(configuration: configuration)
    }

    @concurrent
    func request<T: Decodable & Sendable>(
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
        let response = try await response(for: request)
        return try JSONDecoder().decode(T.self, from: jsonData(response.data))
    }

    @concurrent
    func requestWithMetadata<T: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem],
        response _: T.Type
    ) async throws -> [String: String] {
        let request = try URLRequestFactory.request(
            profile: profile,
            path: path,
            query: query,
            timeoutInterval: requestTimeout
        )
        let response = try await response(for: request)
        _ = try JSONDecoder().decode(T.self, from: jsonData(response.data))
        return response.http.normalizedHeaders
    }

    @concurrent
    func request<T: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem],
        method: String,
        body: Data?,
        response _: T.Type
    ) async throws -> T {
        let request = try URLRequestFactory.request(
            profile: profile,
            path: path,
            query: query,
            method: method,
            body: body,
            timeoutInterval: requestTimeout
        )
        let response = try await response(for: request)
        return try JSONDecoder().decode(T.self, from: jsonData(response.data))
    }

    @concurrent
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
        _ = try await response(for: request)
    }

    @concurrent
    func rawData(
        path: String,
        query: [URLQueryItem],
        method: String,
        body: Data?
    ) async throws -> Data {
        let request = try URLRequestFactory.request(
            profile: profile,
            path: path,
            query: query,
            method: method,
            body: body,
            timeoutInterval: requestTimeout
        )
        return try await response(for: request).data
    }

    func webSocketStream<T: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem],
        response: T.Type,
        appendsSecretToken: Bool = false,
        bufferingPolicy: AsyncThrowingStream<T, Error>.Continuation.BufferingPolicy =
            .bufferingNewest(1)
    ) -> AsyncThrowingStream<T, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: T.self,
            throwing: Error.self,
            bufferingPolicy: bufferingPolicy
        )

        do {
            let request = try webSocketRequest(
                path: path,
                query: query,
                appendsSecretToken: appendsSecretToken
            )
            let webSocketTask = session.webSocketTask(with: request)
            webSocketTask.resume()

            let receiverTask = Task {
                let decoder = JSONDecoder()
                do {
                    while !Task.isCancelled {
                        let message = try await webSocketTask.receive()
                        let data: Data
                        switch message {
                        case .data(let value):
                            data = value
                        case .string(let value):
                            data = Data(value.utf8)
                        @unknown default:
                            continue
                        }
                        continuation.yield(
                            try decoder.decode(response, from: data)
                        )
                    }
                    continuation.finish()
                } catch where Task.isCancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                receiverTask.cancel()
                webSocketTask.cancel(with: .goingAway, reason: nil)
            }
        } catch {
            continuation.finish(throwing: error)
        }
        return stream
    }

    func escaped(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/%?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func response(for request: URLRequest) async throws -> (
        data: Data, http: HTTPURLResponse
    ) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let errorBodyLimit = 16_384
            throw BackendError.httpStatus(
                http.statusCode,
                String(bytes: data.prefix(errorBodyLimit), encoding: .utf8) ?? ""
            )
        }
        return (data, http)
    }

    private func jsonData(_ data: Data) -> Data {
        data.isEmpty ? Data("{}".utf8) : data
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

private extension HTTPURLResponse {
    nonisolated var normalizedHeaders: [String: String] {
        Dictionary(
            allHeaderFields.compactMap { rawKey, value in
                guard let headerName = rawKey as? String else { return nil }
                return (headerName.lowercased(), String(describing: value))
            },
            uniquingKeysWith: { _, latest in latest }
        )
    }
}

nonisolated private final class BackendServerTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    nonisolated func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @Sendable (
            URLSession.AuthChallengeDisposition, URLCredential?
        ) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
