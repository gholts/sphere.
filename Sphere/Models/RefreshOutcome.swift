import Foundation

struct RefreshOutcome {
    var connectionFailed = false
    var backendConnected = false
    var errorMessage: String?
    
    init() {
        // Keeps explicit empty outcome construction at call sites.
    }
    
    init(error: Error) {
        guard !error.isCancellation else { return }
        connectionFailed = error.isConnectionFailure
        errorMessage = error.localizedDescription
    }
    
    mutating func merge(_ other: Self) {
        connectionFailed = connectionFailed || other.connectionFailed
        backendConnected = backendConnected || other.backendConnected
        errorMessage = other.errorMessage ?? errorMessage
    }
    
    mutating func markBackendConnected() {
        backendConnected = true
    }
}
