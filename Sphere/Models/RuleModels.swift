import Foundation

nonisolated struct RuleItem: Identifiable, Codable, Equatable, Sendable {
    var id: String {
        if let index {
            return "\(index)-\(type)-\(payload)-\(proxy)"
        }
        return "\(type)-\(payload)-\(proxy)"
    }
    var type: String
    var payload: String
    var proxy: String
    var index: Int?
    
    enum CodingKeys: String, CodingKey {
        case type
        case payload
        case proxy
        case index
    }
    
    var isRuleSet: Bool {
        ["ruleset", "rule-set", "rule_set"].contains(normalizedType)
    }
    
    var isMatch: Bool {
        normalizedType == "match"
    }
    
    var displayTitle: String {
        if isMatch {
            return "Match"
        }
        let value = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? type : value
    }
    
    private var normalizedType: String {
        type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    init(type: String, payload: String, proxy: String, index: Int? = nil) {
        self.type = type
        self.payload = payload
        self.proxy = Self.cleanProxyName(proxy)
        self.index = index
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        payload = try container.decodeIfPresent(String.self, forKey: .payload) ?? ""
        proxy = Self.cleanProxyName(try container.decodeIfPresent(String.self, forKey: .proxy) ?? "")
        index = try container.decodeIfPresent(Int.self, forKey: .index)
    }
    
    private static func cleanProxyName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("route("), trimmed.hasSuffix(")") else {
            return value
        }
        return String(trimmed.dropFirst(6).dropLast())
    }
}

nonisolated struct RuleCollection: Codable, Equatable, Sendable {
    var rules: [RuleItem]
}

nonisolated struct RuleProvider: Identifiable, Codable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var type: String?
    var vehicleType: String?
    var behavior: String?
    var format: String?
    var updatedAt: String?
    var ruleCount: Int?
    
    var isRemote: Bool {
        vehicleType?.caseInsensitiveCompare("Inline") != .orderedSame
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case type
        case vehicleType
        case behavior
        case format
        case updatedAt
        case ruleCount
    }
    
    init(
        name: String,
        type: String? = nil,
        vehicleType: String? = nil,
        behavior: String? = nil,
        format: String? = nil,
        updatedAt: String? = nil,
        ruleCount: Int? = nil
    ) {
        self.name = name
        self.type = type
        self.vehicleType = vehicleType
        self.behavior = behavior
        self.format = format
        self.updatedAt = updatedAt
        self.ruleCount = ruleCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type)
        vehicleType = try container.decodeIfPresent(String.self, forKey: .vehicleType)
        behavior = try container.decodeIfPresent(String.self, forKey: .behavior)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        ruleCount = try container.decodeIfPresent(Int.self, forKey: .ruleCount)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(vehicleType, forKey: .vehicleType)
        try container.encodeIfPresent(behavior, forKey: .behavior)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(ruleCount, forKey: .ruleCount)
    }
}
