import Foundation

nonisolated struct AppNavigationRequest: Identifiable, Equatable, Sendable {
    var id: UUID
    var destination: AppNavigationDestination

    init(destination: AppNavigationDestination) {
        self.id = UUID()
        self.destination = destination
    }

    init(id: UUID, destination: AppNavigationDestination) {
        self.id = id
        self.destination = destination
    }
}

nonisolated enum AppNavigationDestination: Equatable, Sendable {
    case tab(AppTab)
    case addProfile
    case editProfile(UUID)
    case configEditor
    case logBook
    case connectionsList

    var targetTab: AppTab {
        switch self {
        case .tab(let tab):
            return tab
        case .addProfile, .editProfile, .configEditor, .logBook:
            return .more
        case .connectionsList:
            return .connections
        }
    }
}
