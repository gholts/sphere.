import Foundation

nonisolated struct SurgePoliciesPayload: Decodable, Equatable, Sendable {
    var names: [String]

    init(from decoder: Decoder) throws {
        names = Self.names(in: try JSONValue(from: decoder)).surgeStableUniqueNames
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

    fileprivate static func namesFromAny(_ value: JSONValue) -> [String] {
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
        let options = items.compactMap { $0.string(for: "name") }.surgeStableUniqueNames
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

extension Array where Element == String {
    nonisolated var surgeStableUniqueNames: [String] {
        var seen: Set<String> = []
        return filter { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && seen.insert(trimmed).inserted
        }
    }
}

private extension Array where Element == ProxyItem {
    nonisolated var stableUniqueItems: [ProxyItem] {
        var seen: Set<String> = []
        return filter { item in
            !item.name.isEmpty && seen.insert(item.name).inserted
        }
    }
}
