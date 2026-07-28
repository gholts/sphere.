import Foundation
import Observation

@Observable
@MainActor
final class LiveState {
    var overview = BackendOverview.empty
    var connections = ConnectionsSnapshot(uploadTotal: nil, downloadTotal: nil, connections: [])
    var devices: [SurgeDevice] = []
    var logs: [LogEntry] = []
    var logLevel: LogLevel = .info

    func resetBackendData() {
        overview = .empty
        connections = ConnectionsSnapshot(uploadTotal: nil, downloadTotal: nil, connections: [])
        devices = []
    }

    func resetLogs() {
        logs = []
        logLevel = .info
    }

    func reset() {
        resetBackendData()
        resetLogs()
    }
}
