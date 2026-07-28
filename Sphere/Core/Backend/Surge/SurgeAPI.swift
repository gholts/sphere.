import Foundation

nonisolated enum SurgeEndpoint: Sendable {
    case outbound
    case outboundGlobal
    case policies
    case policiesTest
    case policyGroups
    case policyGroupSelection
    case policyGroupTest
    case requestsActive
    case requestsKill
    case profilesReload
    case rules
    case traffic
    case events
    case modules
    case feature(SurgeFeature)
    case logLevel
    case devices
    case dns
    case dnsFlush
    case stop
    case mitmCertificate

    var path: String {
        switch self {
        case .outbound:
            "/v1/outbound"
        case .outboundGlobal:
            "/v1/outbound/global"
        case .policies:
            "/v1/policies"
        case .policiesTest:
            "/v1/policies/test"
        case .policyGroups:
            "/v1/policy_groups"
        case .policyGroupSelection:
            "/v1/policy_groups/select"
        case .policyGroupTest:
            "/v1/policy_groups/test"
        case .requestsActive:
            "/v1/requests/active"
        case .requestsKill:
            "/v1/requests/kill"
        case .profilesReload:
            "/v1/profiles/reload"
        case .rules:
            "/v1/rules"
        case .traffic:
            "/v1/traffic"
        case .events:
            "/v1/events"
        case .modules:
            "/v1/modules"
        case .feature(let feature):
            "/v1/features/\(feature.rawValue)"
        case .logLevel:
            "/v1/log/level"
        case .devices:
            "/v1/devices"
        case .dns:
            "/v1/dns"
        case .dnsFlush:
            "/v1/dns/flush"
        case .stop:
            "/v1/stop"
        case .mitmCertificate:
            "/v1/mitm/ca"
        }
    }
}

nonisolated struct SurgeAPI: Sendable {
    private let transport: BackendTransport

    init(transport: BackendTransport) {
        self.transport = transport
    }

    @concurrent
    func get<Value: Decodable & Sendable>(
        _ endpoint: SurgeEndpoint,
        query: [URLQueryItem],
        as _: Value.Type
    ) async throws -> Value {
        try await retryingGet {
            try await transport.request(
                path: endpoint.path,
                query: query,
                response: Value.self
            )
        }
    }

    @concurrent
    func getWithMetadata<Value: Decodable & Sendable>(
        _ endpoint: SurgeEndpoint,
        query: [URLQueryItem],
        as _: Value.Type
    ) async throws -> [String: String] {
        try await retryingGet {
            try await transport.requestWithMetadata(
                path: endpoint.path,
                query: query,
                response: Value.self
            )
        }
    }

    @concurrent
    func getData(_ endpoint: SurgeEndpoint) async throws -> Data {
        try await retryingGet {
            try await transport.rawData(
                path: endpoint.path,
                query: [],
                method: "GET",
                body: nil
            )
        }
    }

    @concurrent
    func post<Body: Encodable & Sendable>(
        _ endpoint: SurgeEndpoint,
        body: Body
    ) async throws {
        let data = try JSONEncoder().encode(body)
        let response = try await transport.rawData(
            path: endpoint.path,
            query: [],
            method: "POST",
            body: data
        )
        try validateMutationResponse(response)
    }

    @concurrent
    func post(_ endpoint: SurgeEndpoint) async throws {
        let response = try await transport.rawData(
            path: endpoint.path,
            query: [],
            method: "POST",
            body: nil
        )
        try validateMutationResponse(response)
    }

    @concurrent
    func post<Value: Decodable & Sendable, Body: Encodable & Sendable>(
        _ endpoint: SurgeEndpoint,
        body: Body,
        as _: Value.Type
    ) async throws -> Value {
        let response = try await transport.rawData(
            path: endpoint.path,
            query: [],
            method: "POST",
            body: JSONEncoder().encode(body)
        )
        try validateMutationResponse(response)
        return try JSONDecoder().decode(Value.self, from: response)
    }

    @concurrent
    func postData(_ endpoint: SurgeEndpoint) async throws -> Data {
        let response = try await transport.rawData(
            path: endpoint.path,
            query: [],
            method: "POST",
            body: nil
        )
        try validateMutationResponse(response)
        return response
    }

    private func retryingGet<Value: Sendable>(
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        var attempt = 0
        while true {
            do {
                try Task.checkCancellation()
                return try await operation()
            } catch {
                attempt += 1
                guard attempt < 2, Self.isRetryable(error) else {
                    throw error
                }
                try await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private func validateMutationResponse(_ data: Data) throws {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
            case .object(let object) = value
        else {
            return
        }

        if let error = object["error"], error != .null, error.boolValue != false {
            let message = error.stringValue ?? "Surge rejected request"
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BackendError.api(trimmed.isEmpty ? "Surge rejected request" : trimmed)
        }
        if object["success"]?.boolValue == false || object["ok"]?.boolValue == false {
            let message = value.trimmedString(for: "message", "detail", "reason")
                ?? "Surge rejected request"
            throw BackendError.api(message)
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                .cannotFindHost,
                .cannotConnectToHost,
                .dnsLookupFailed,
                .networkConnectionLost,
                .notConnectedToInternet,
                .resourceUnavailable,
                .cannotLoadFromNetwork:
                return true
            default:
                return false
            }
        }
        if case .httpStatus(let status, _) = error as? BackendError {
            return status == 408 || status == 429 || status >= 500
        }
        return false
    }
}
