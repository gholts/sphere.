import Foundation

extension SurgeClient {
    func connections() async throws -> ConnectionsSnapshot {
        let connections = try await api.get(
            .requestsActive,
            query: [],
            as: SurgeRequestsPayload.self
        ).connections
        return ConnectionsSnapshot(
            uploadTotal: connections.reduce(0) { $0 + $1.upload },
            downloadTotal: connections.reduce(0) { $0 + $1.download },
            connections: connections
        )
    }

    func closeConnection(_ id: String) async throws {
        guard let numericID = Int(id) else {
            throw BackendError.api("Invalid Surge request ID: \(id)")
        }
        try await api.post(.requestsKill, body: SurgeRequestID(id: numericID))
    }

    func closeAllConnections() async throws {
        let connections = try await connections().connections
        var iterator = connections.makeIterator()

        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for _ in 0..<4 {
                guard let connection = iterator.next() else {
                    break
                }
                taskGroup.addTask {
                    try await closeConnection(connection.id)
                }
            }

            while try await taskGroup.next() != nil {
                guard let connection = iterator.next() else {
                    continue
                }
                taskGroup.addTask {
                    try await closeConnection(connection.id)
                }
            }
        }
    }
}

nonisolated private struct SurgeRequestID: Encodable, Sendable {
    var id: Int
}
