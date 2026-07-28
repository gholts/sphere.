import Foundation

nonisolated struct SurgeRulesPayload: Decodable, Equatable, Sendable {
    var rules: [RuleItem]

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        let rawRules =
            value.array(for: "rules").isEmpty
            ? value.arrayValue
            : value.array(for: "rules")
        rules = rawRules.enumerated().compactMap { index, value in
            Self.rule(from: value, index: index)
        }
    }

    private static func rule(
        from value: JSONValue,
        index: Int
    ) -> RuleItem? {
        if let line = value.stringValue {
            let parts = line.surgeRuleFields
            guard let type = parts.first, !type.isEmpty else { return nil }
            guard !type.hasPrefix("#") else { return nil }
            guard parts.count >= 2 else { return nil }
            let payload: String
            let proxy: String
            if parts.count == 2 {
                payload = ""
                proxy = parts[1]
            } else {
                payload = parts[1]
                proxy = parts[2]
            }
            return RuleItem(
                type: type,
                payload: payload,
                proxy: proxy,
                index: index
            )
        }
        guard case .object = value else { return nil }
        let type = value.string(for: "type", "rule", "rule_type") ?? ""
        guard !type.isEmpty else { return nil }
        let payload =
            value.string(
                for: "payload",
                "value",
                "parameter",
                "pattern"
            ) ?? ""
        let proxy =
            value.string(for: "proxy", "policy", "target") ?? ""
        return RuleItem(
            type: type,
            payload: payload,
            proxy: proxy,
            index: value.int(for: "index") ?? index
        )
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
                fields.append(
                    current.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                )
                current = ""
            default:
                current.append(character)
            }
        }
        fields.append(
            current.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return fields
    }
}
