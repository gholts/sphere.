import Foundation

nonisolated struct SurgePolicyTestPayload: Decodable, Equatable, Sendable {
    var delays: [String: Int]

    init(from decoder: Decoder) throws {
        delays = Self.delays(in: try JSONValue(from: decoder))
    }

    private static func delays(in value: JSONValue) -> [String: Int] {
        if let delay = value.int(for: "receive", "delay", "latency", "rtt") {
            return ["": delay]
        }
        switch value {
        case .array(let values):
            return values.reduce(into: [:]) { result, item in
                result.merge(delays(in: item), uniquingKeysWith: { current, _ in current })
            }
        case .object(let object):
            return delays(in: object)
        default:
            return [:]
        }
    }

    private static func delays(in object: [String: JSONValue]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (key, item) in object {
            if let delay = item.intValue {
                if !["time", "timestamp", "winner"].contains(key) {
                    result[key] = delay
                }
            } else if let delay = item.int(for: "receive", "delay", "latency", "time", "rtt") {
                result[key] = delay
            } else {
                result.merge(
                    delays(in: item),
                    uniquingKeysWith: { current, _ in current }
                )
            }
        }
        return result
    }
}
