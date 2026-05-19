import Foundation

nonisolated enum CoreUpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case release
    case alpha
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .release:
            return "Release"
        case .alpha:
            return "Alpha"
        }
    }
}

nonisolated struct CoreUpdateReport: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case success
        case failure
        case skipped
    }
    
    var channel: CoreUpdateChannel
    var status: Status
    var message: String
    
    var title: String {
        switch status {
        case .success:
            return "Update Finished"
        case .failure:
            return "Update Failed"
        case .skipped:
            return "Update Unavailable"
        }
    }
    
    var systemImage: String {
        switch status {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        case .skipped:
            return "exclamationmark.triangle.fill"
        }
    }
    
    static func success(channel: CoreUpdateChannel) -> Self {
        Self(channel: channel, status: .success, message: "\(channel.title) core update finished.")
    }
    
    static func failure(channel: CoreUpdateChannel, message: String) -> Self {
        Self(channel: channel, status: .failure, message: "\(channel.title) core update failed. \(message)")
    }
    
    static func skipped(channel: CoreUpdateChannel) -> Self {
        Self(channel: channel, status: .skipped, message: "Core update unavailable for current backend.")
    }
}
