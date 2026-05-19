import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case proxies
    case rule
    case connections
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .proxies:
            return "Proxies"
        case .rule:
            return "Rule"
        case .connections:
            return "Connections"
        case .more:
            return "More"
        }
    }

    var symbol: String {
        switch self {
        case .proxies:
            return "point.3.connected.trianglepath.dotted"
        case .rule:
            return "list.bullet.rectangle"
        case .connections:
            return "bolt.horizontal.circle"
        case .more:
            return "ellipsis.circle"
        }
    }
}
