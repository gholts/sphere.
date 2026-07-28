import Foundation

extension SurgeClient {
    func devices() async throws -> [SurgeDevice] {
        do {
            return try await api.get(
                .devices,
                query: [],
                as: SurgeDevicesPayload.self
            ).devices
        } catch BackendError.httpStatus(404, _) {
            return []
        }
    }

    func updateDevice(_ update: SurgeDevice.Update) async throws {
        try await api.post(.devices, body: update)
    }
}
