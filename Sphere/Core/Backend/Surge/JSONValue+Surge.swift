import Foundation

extension JSONValue {
    nonisolated var objectValue: [String: JSONValue] {
        if case .object(let values) = self { return values }
        return [:]
    }

    nonisolated var arrayValue: [JSONValue] {
        if case .array(let values) = self { return values }
        return []
    }

    nonisolated var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return Int(exactly: value).map(String.init) ?? String(value)
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    nonisolated var trimmedScalarString: String? {
        guard case .string(let value) = self else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated func trimmedString(for keys: String...) -> String? {
        for key in keys {
            if let value = objectValue[key]?.trimmedScalarString {
                return value
            }
        }
        return nil
    }

    nonisolated func string(for keys: String...) -> String? {
        for key in keys {
            if let value = objectValue[key]?.stringValue {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    nonisolated func int(for keys: String...) -> Int? {
        for key in keys {
            if let value = objectValue[key]?.intValue {
                return value
            }
        }
        return nil
    }

    nonisolated func bool(for keys: String...) -> Bool? {
        for key in keys {
            if let value = objectValue[key]?.boolValue {
                return value
            }
        }
        return nil
    }

    nonisolated var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(exactly: value)
        case .string(let value):
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    nonisolated var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    nonisolated func array(for key: String) -> [JSONValue] {
        objectValue[key]?.arrayValue ?? []
    }

    nonisolated func stringArray(for keys: String...) -> [String] {
        for key in keys {
            let values = objectValue[key]?.stringArrayValue ?? []
            if !values.isEmpty {
                return values
            }
        }
        return []
    }

    nonisolated var stringArrayValue: [String] {
        switch self {
        case .array(let values):
            return values.compactMap(\.stringValue).surgeStableUniqueNames
        case .string(let value):
            return [value].surgeStableUniqueNames
        default:
            return []
        }
    }

    nonisolated var trafficSnapshot: TrafficSnapshot {
        if let up = int(for: "up", "upload", "uploadSpeed", "upload_speed", "tx"),
            let down = int(for: "down", "download", "downloadSpeed", "download_speed", "rx") {
            return TrafficSnapshot(up: up, down: down)
        }
        if let connector = objectValue["connector"] {
            return connector.summedTrafficSnapshot
        }
        if let interface = objectValue["interface"] {
            return interface.summedTrafficSnapshot
        }
        return TrafficSnapshot(up: 0, down: 0)
    }

    nonisolated var summedTrafficSnapshot: TrafficSnapshot {
        guard case .object(let values) = self else { return TrafficSnapshot(up: 0, down: 0) }
        return values.values.reduce(TrafficSnapshot(up: 0, down: 0)) { partial, value in
            TrafficSnapshot(
                up: partial.up + (value.int(for: "outCurrentSpeed", "outSpeed", "uploadSpeed") ?? 0),
                down: partial.down + (value.int(for: "inCurrentSpeed", "inSpeed", "downloadSpeed") ?? 0)
            )
        }
    }
}
