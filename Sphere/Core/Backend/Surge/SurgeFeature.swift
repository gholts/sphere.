import Foundation

nonisolated enum SurgeFeature: String, CaseIterable, Sendable {
    case mitm
    case capture
    case rewrite
    case scripting
    case systemProxy = "system_proxy"
    case enhancedMode = "enhanced_mode"

    var configKey: String { rawValue }
}

nonisolated struct SurgeFeaturePayload: Codable, Equatable, Sendable {
    var enabled: Bool
}
