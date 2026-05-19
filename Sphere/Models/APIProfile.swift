import Foundation

nonisolated enum BackendKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case mihomo
    case singbox
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .mihomo:
            return "Mihomo"
        case .singbox:
            return "Singbox"
        }
    }
    
    var isImplemented: Bool {
        self == .mihomo || self == .singbox
    }
    
    var showsProxyProviders: Bool {
        self == .mihomo
    }
    
    static func detected(fromVersion version: String) -> Self? {
        let lowercased = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return nil }
        if lowercased.contains("sing-box") || lowercased.contains("singbox") {
            return .singbox
        }
        if lowercased.contains("mihomo") || lowercased.contains("meta") || lowercased.contains("clash") {
            return .mihomo
        }
        return nil
    }
}

nonisolated struct APIProfile: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var kind: BackendKind
    var baseURL: String
    var secret: String
    
    init(
        id: UUID = UUID(),
        name: String,
        kind: BackendKind = .mihomo,
        baseURL: String,
        secret: String
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = URLNormalizer.normalizedBaseURL(baseURL)
        self.secret = secret
    }
    
    var url: URL? {
        URL(string: URLNormalizer.normalizedBaseURL(baseURL))
    }
}

nonisolated enum URLNormalizer {
    static func normalizedBaseURL(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return value
        }
        if !value.contains("://") {
            value = "http://" + value
        }
        while value.hasSuffix("/"), !value.hasSuffix("://") {
            value.removeLast()
        }
        return value
    }
}

nonisolated enum ProfileCodec {
    static func decode(_ data: Data) -> [APIProfile] {
        (try? JSONDecoder().decode([APIProfile].self, from: data)) ?? []
    }
    
    @concurrent
    static func decodeAsync(_ data: Data) async -> [APIProfile] {
        decode(data)
    }
    
    static func encode(_ profiles: [APIProfile]) -> Data {
        (try? JSONEncoder().encode(profiles)) ?? Data()
    }
}
