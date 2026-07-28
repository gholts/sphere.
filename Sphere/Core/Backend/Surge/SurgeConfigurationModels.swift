import Foundation

nonisolated struct SurgeOutboundPayload: Decodable, Equatable, Sendable {
    var mode: String

    init(mode: String) {
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        mode = value.string(for: "mode") ?? "rule"
    }

    var clashMode: ClashMode {
        switch mode.lowercased() {
        case "direct":
            return .direct
        case "proxy", "global":
            return .global
        default:
            return .rule
        }
    }
}

nonisolated struct SurgeGlobalPolicyPayload: Decodable, Equatable, Sendable {
    var policy: String

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        policy = value.string(for: "policy") ?? ""
    }
}

nonisolated struct SurgeModulesPayload: Decodable, Equatable, Sendable {
    var enabled: [String]
    var available: [String]

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        enabled = value.stringArray(for: "enabled")
        let availableValues = value.stringArray(for: "available")
        available = availableValues.isEmpty ? enabled : availableValues
    }
}
