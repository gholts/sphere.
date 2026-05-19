import ActivityKit
import Foundation

nonisolated enum SphereProgressActivityKind: String, Codable, Hashable, Sendable {
    case coreUpdate = "core_update"
    case latencyTest = "latency_test"

    var title: String {
        switch self {
        case .coreUpdate:
            return "Core Update"
        case .latencyTest:
            return "Latency Test"
        }
    }

    var systemImage: String {
        switch self {
        case .coreUpdate:
            return "arrow.down.circle"
        case .latencyTest:
            return "speedometer"
        }
    }
}

nonisolated enum SphereProgressActivityStatus: String, Codable, Hashable, Sendable {
    case running
    case succeeded
    case failed
}

nonisolated struct SphereProgressActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var title: String
        var detail: String
        var fraction: Double
        var status: SphereProgressActivityStatus

        var clampedFraction: Double {
            min(max(fraction, 0), 1)
        }

        var percentText: String {
            "\(Int((clampedFraction * 100).rounded()))%"
        }
    }

    var operationID: String
    var kind: SphereProgressActivityKind
}
