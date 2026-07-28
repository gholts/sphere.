import Foundation

nonisolated struct SurgeTrafficPayload: Decodable, Equatable, Sendable {
    var snapshot: TrafficSnapshot

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        snapshot = value.trafficSnapshot
    }
}
