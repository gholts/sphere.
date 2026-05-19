import Foundation

nonisolated enum JSONValue: Codable, Hashable, Sendable {
    case object([String: Self])
    case array([Self])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    
    var displayText: String {
        switch self {
        case .object(let values):
            return "{\(values.count) fields}"
        case .array(let values):
            return "[\(values.count) items]"
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }
    
    var isScalar: Bool {
        switch self {
        case .string, .number, .bool, .null:
            return true
        case .object, .array:
            return false
        }
    }
    
    init(from decoder: Decoder) throws {
        if let object = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var values: [String: Self] = [:]
            values.reserveCapacity(object.allKeys.count)
            for key in object.allKeys {
                values[key.stringValue] = try object.decode(Self.self, forKey: key)
            }
            self = .object(values)
            return
        }
        
        if var array = try? decoder.unkeyedContainer() {
            var values: [Self] = []
            values.reserveCapacity(array.count ?? 0)
            while !array.isAtEnd {
                values.append(try array.decode(Self.self))
            }
            self = .array(values)
            return
        }
        
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let values):
            try container.encode(values)
        case .array(let values):
            try container.encode(values)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

nonisolated enum JSONScalarParser {
    static func parse(_ text: String, fallback: JSONValue) -> JSONValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch fallback {
        case .bool:
            return .bool(["true", "1", "yes", "on"].contains(trimmed.lowercased()))
        case .number:
            return .number(Double(trimmed) ?? 0)
        case .null:
            return trimmed.isEmpty || trimmed.lowercased() == "null" ? .null : .string(trimmed)
        case .string:
            return .string(text)
        case .object, .array:
            return fallback
        }
    }
}
