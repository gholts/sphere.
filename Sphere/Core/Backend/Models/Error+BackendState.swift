import Foundation

extension Error {
    nonisolated var isCancellation: Bool {
        if self is CancellationError { return true }
        return (self as? URLError)?.code == .cancelled
    }

    nonisolated var isConnectionFailure: Bool {
        guard let error = self as? URLError else { return false }
        switch error.code {
        case .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
            .secureConnectionFailed,
            .serverCertificateUntrusted:
            return true
        default:
            return false
        }
    }
}
