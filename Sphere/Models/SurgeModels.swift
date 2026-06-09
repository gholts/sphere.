import Foundation

nonisolated enum SurgeFeature: String, CaseIterable, Sendable {
    case mitm
    case capture
    case rewrite
    case scripting
    case systemProxy = "system_proxy"
    case enhancedMode = "enhanced_mode"

    var configKey: String { rawValue }
}

nonisolated struct SurgeFeaturePayload: Codable, Equatable, Sendable {
    var enabled: Bool
}

nonisolated struct SurgeOutboundPayload: Decodable, Equatable, Sendable {
    var mode: String

    init(mode: String) {
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        mode = value.string(for: "mode") ?? "rule"
    }

    var clashMode: ClashMode {
        switch mode.lowercased() {
        case "direct":
            return .direct
        case "proxy", "global":
            return .global
        default:
            return .rule
        }
    }
}

nonisolated struct SurgeGlobalPolicyPayload: Decodable, Equatable, Sendable {
    var policy: String

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        policy = value.string(for: "policy") ?? ""
    }
}

nonisolated struct SurgeModulesPayload: Decodable, Equatable, Sendable {
    var enabled: [String]
    var available: [String]

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        enabled = value.stringArray(for: "enabled")
        let availableValues = value.stringArray(for: "available")
        available = availableValues.isEmpty ? enabled : availableValues
    }
}

nonisolated struct SurgePoliciesPayload: Decodable, Equatable, Sendable {
    var names: [String]

    init(from decoder: Decoder) throws {
        names = Self.names(in: try JSONValue(from: decoder)).stableUniqueValues
    }

    private static func names(in value: JSONValue) -> [String] {
        switch value {
        case .array(let values):
            return values.flatMap(names(in:))
        case .object(let object):
            if object["proxies"] != nil || object["policy-groups"] != nil {
                return names(in: object["proxies"] ?? .array([]))
                    + names(in: object["policy-groups"] ?? .array([]))
            }
            for key in ["policies", "policy_names", "policyNames", "available"] {
                if let nested = object[key] {
                    return names(in: nested)
                }
            }
            if let name = value.string(for: "name", "policy", "policy_name") {
                return [name]
            }
            return object.keys.sorted()
        case .string(let name):
            return [name]
        default:
            return []
        }
    }
}

nonisolated struct SurgePolicyGroupsPayload: Decodable, Equatable, Sendable {
    var groups: [ProxyItem]

    init(from decoder: Decoder) throws {
        groups = Self.groups(in: try JSONValue(from: decoder)).stableUniqueItems
    }

    private static func groups(in value: JSONValue) -> [ProxyItem] {
        switch value {
        case .array(let values):
            return values.compactMap { group(from: $0) }
        case .object(let object):
            for key in ["groups", "policy_groups", "policyGroups"] {
                if let nested = object[key] {
                    return groups(in: nested)
                }
            }
            if value.string(for: "name", "group_name", "groupName") != nil {
                return group(from: value).map { [$0] } ?? []
            }
            return object.sorted { $0.key < $1.key }.compactMap { name, value in
                if case .object = value {
                    return group(from: value, fallbackName: name)
                }
                if case .array(let items) = value {
                    return group(name: name, items: items)
                }
                let options = SurgePoliciesPayload.namesFromAny(value)
                return ProxyItem(name: name, type: "Selector", all: options)
            }
        default:
            return []
        }
    }

    private static func group(from value: JSONValue, fallbackName: String? = nil) -> ProxyItem? {
        guard let name = value.string(for: "name", "group_name", "groupName") ?? fallbackName else {
            return nil
        }
        let type = value.string(for: "type", "group_type", "policy_type") ?? "Selector"
        let all =
            [
                value.stringArray(for: "policies"),
                value.stringArray(for: "options"),
                value.stringArray(for: "all"),
                value.stringArray(for: "available"),
            ]
            .first { !$0.isEmpty } ?? []
        let now = value.string(for: "now", "selected", "policy", "current", "currentPolicy")
        return ProxyItem(name: name, type: type, now: now, all: all)
    }

    private static func group(name: String, items: [JSONValue]) -> ProxyItem {
        let options = items.compactMap { $0.string(for: "name") }.stableUniqueValues
        let type =
            items.first { $0.bool(for: "isGroup") == true }?
            .string(for: "typeDescription", "type", "policy_type")
            ?? items.first?.string(for: "typeDescription", "type", "policy_type")
            ?? "Policy Group"
        return ProxyItem(name: name, type: type, all: options)
    }
}

nonisolated struct SurgePolicySelectionPayload: Decodable, Equatable, Sendable {
    var policy: String?

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        policy = value.string(for: "policy", "selected", "now", "current", "currentPolicy")
    }
}

nonisolated struct SurgePolicyTestPayload: Decodable, Equatable, Sendable {
    var delays: [String: Int]

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        delays = Self.delays(in: value)
    }

    private static func delays(in value: JSONValue) -> [String: Int] {
        if let delay = value.int(for: "delay", "latency", "time") {
            return ["": delay]
        }
        guard case .object(let object) = value else { return [:] }
        for key in ["results", "delays", "delay", "test_results", "testResults"] {
            if let nested = object[key] {
                let values = delays(in: nested)
                if !values.isEmpty { return values }
            }
        }
        var result: [String: Int] = [:]
        for (key, item) in object {
            switch item {
            case .number(let delay):
                result[key] = Int(delay)
            case .object:
                if let delay = item.int(for: "delay", "latency", "time", "rtt") {
                    result[key] = delay
                } else {
                    result.merge(delays(in: item), uniquingKeysWith: { current, _ in current })
                }
            default:
                break
            }
        }
        return result
    }
}

nonisolated struct SurgeGroupTestPayload: Decodable, Equatable, Sendable {
    var available: [String]

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        available = value.stringArray(for: "available")
    }
}

nonisolated enum SurgeRefreshMessage {
    static func message(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            let message =
                value.string(for: "message", "result", "status", "detail")
                ?? value.stringValue
                ?? value.prettyJSONText
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return text.isEmpty ? nil : text
    }
}

nonisolated struct SurgeRulesPayload: Decodable, Equatable, Sendable {
    var rules: [RuleItem]

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        let rawRules = value.array(for: "rules").isEmpty ? value.arrayValue : value.array(for: "rules")
        rules = rawRules.enumerated().compactMap { index, value in
            Self.rule(from: value, index: index)
        }
    }

    private static func rule(from value: JSONValue, index: Int) -> RuleItem? {
        if let line = value.stringValue {
            let parts = line.surgeRuleFields
            guard let type = parts.first, !type.isEmpty else { return nil }
            guard !type.hasPrefix("#") else { return nil }
            let payload: String
            let proxy: String
            if parts.count == 2 {
                payload = ""
                proxy = parts[1]
            } else {
                payload = parts[1]
                proxy = parts[2]
            }
            return RuleItem(type: type, payload: payload, proxy: proxy, index: index)
        }
        guard case .object = value else { return nil }
        let type = value.string(for: "type", "rule", "rule_type") ?? ""
        guard !type.isEmpty else { return nil }
        let payload = value.string(for: "payload", "value", "parameter", "pattern") ?? ""
        let proxy = value.string(for: "proxy", "policy", "target") ?? ""
        return RuleItem(type: type, payload: payload, proxy: proxy, index: value.int(for: "index") ?? index)
    }
}

nonisolated struct SurgeRequestsPayload: Decodable, Equatable, Sendable {
    var connections: [ConnectionInfo]

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        let requests =
            [
                value.array(for: "requests"),
                value.array(for: "active"),
                value.array(for: "recent"),
                value.array(for: "connections"),
                value.arrayValue,
            ]
            .first { !$0.isEmpty } ?? []
        connections = requests.enumerated().compactMap { index, request in
            Self.connection(from: request, index: index)
        }
    }

    private static func connection(from value: JSONValue, index: Int) -> ConnectionInfo? {
        guard case .object = value else { return nil }
        let id = value.string(for: "id", "request_id", "requestID")
            ?? value.int(for: "id").map(String.init)
            ?? String(index)
        let host = value.string(for: "host", "hostname", "domain", "url", "URL")
        let destinationIP = value.string(
            for: "destinationIP", "destination_ip", "remoteAddress", "remote_address",
            "address", "ip")
        let sourceIP = value.string(
            for: "sourceIP", "source_ip", "sourceAddress", "source_address", "client")
        let metadata = ConnectionMetadata(
            network: value.string(for: "network", "protocol"),
            type: value.string(for: "type", "request_type", "method"),
            sourceIP: sourceIP,
            destinationIP: destinationIP,
            host: host,
            process: value.string(for: "process", "processName", "process_name")
        )
        let policy = value.string(for: "policy", "outbound", "proxy") ?? ""
        return ConnectionInfo(
            id: id,
            metadata: metadata,
            upload: Int64(value.int(for: "upload", "uploadBytes", "upload_bytes") ?? 0),
            download: Int64(value.int(for: "download", "downloadBytes", "download_bytes") ?? 0),
            start: value.string(for: "start", "created", "startTime", "start_time"),
            chains: policy.isEmpty ? [] : [policy],
            rule: value.string(for: "rule", "ruleName", "rule_name"),
            rulePayload: value.string(for: "rulePayload", "rule_payload", "ruleValue")
        )
    }
}

nonisolated struct SurgeTrafficPayload: Decodable, Equatable, Sendable {
    var snapshot: TrafficSnapshot

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        snapshot = value.trafficSnapshot
    }
}

nonisolated struct SurgeEventsPayload: Decodable, Equatable, Sendable {
    var logs: [LogEntry]

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        let events =
            [
                value.array(for: "events"),
                value.array(for: "logs"),
                value.array(for: "items"),
                value.arrayValue,
            ]
            .first { !$0.isEmpty } ?? []
        logs = events.compactMap(Self.logEntry(from:))
    }

    private static func logEntry(from value: JSONValue) -> LogEntry? {
        if let message = value.stringValue {
            return LogEntry(type: "info", payload: message)
        }
        guard case .object = value else { return nil }
        let payload =
            value.string(for: "message", "payload", "content", "title", "event") ?? value.prettyJSONText
        return LogEntry(type: logType(from: value, payload: payload), payload: payload)
    }

    private static func logType(from value: JSONValue, payload: String) -> String {
        if let numericType = value.int(for: "type") {
            return normalizedNumericType(numericType, payload: payload)
        }
        if let rawType = value.string(for: "level", "category", "severity", "type") {
            return normalizedTextType(rawType, payload: payload)
        }
        return inferredType(from: payload)
    }

    private static func normalizedNumericType(_ type: Int, payload: String) -> String {
        switch type {
        case ..<1:
            return inferredType(from: payload)
        case 1:
            return "warning"
        default:
            return "error"
        }
    }

    private static func normalizedTextType(_ type: String, payload: String) -> String {
        let lowercased = type.lowercased()
        if ["verbose", "debug"].contains(lowercased) { return "debug" }
        if ["warn", "warning"].contains(lowercased) { return "warning" }
        if ["error", "fault", "critical"].contains(lowercased) { return "error" }
        if ["info", "notice", "notify"].contains(lowercased) { return "info" }
        return inferredType(from: payload)
    }

    private static func inferredType(from payload: String) -> String {
        let lowercased = payload.lowercased()
        if lowercased.localizedStandardContains("error")
            || lowercased.localizedStandardContains("failed")
            || lowercased.localizedStandardContains("failure") {
            return "error"
        }
        if lowercased.localizedStandardContains("warn") {
            return "warning"
        }
        if lowercased.localizedStandardContains("debug")
            || lowercased.localizedStandardContains("verbose") {
            return "debug"
        }
        return "info"
    }
}

fileprivate extension SurgePoliciesPayload {
    nonisolated static func namesFromAny(_ value: JSONValue) -> [String] {
        switch value {
        case .array(let values):
            return values.compactMap(\.stringValue)
        case .string(let name):
            return [name]
        case .object(let object):
            return object.keys.sorted()
        default:
            return []
        }
    }
}

private extension Array where Element == String {
    nonisolated var stableUniqueValues: [String] {
        var seen: Set<String> = []
        return filter { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return false }
            seen.insert(trimmed)
            return true
        }
    }
}

private extension Array where Element == ProxyItem {
    nonisolated var stableUniqueItems: [ProxyItem] {
        var seen: Set<String> = []
        return filter { item in
            guard !item.name.isEmpty, !seen.contains(item.name) else { return false }
            seen.insert(item.name)
            return true
        }
    }
}

private extension JSONValue {
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
            return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
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
            return Int(value)
        case .string(let value):
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    nonisolated var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
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
            return values.compactMap(\.stringValue).stableUniqueValues
        case .string(let value):
            return [value].stableUniqueValues
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

private extension String {
    nonisolated var surgeRuleFields: [String] {
        var fields: [String] = []
        var current = ""
        var isQuoted = false
        var iterator = makeIterator()
        while let character = iterator.next() {
            switch character {
            case "\"":
                isQuoted.toggle()
            case "," where !isQuoted:
                fields.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            default:
                current.append(character)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return fields
    }
}
