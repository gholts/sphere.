import Foundation

nonisolated struct SurgeEvent: Equatable, Sendable {
    var identity: String
    var entry: LogEntry
}

nonisolated struct SurgeEventsPayload: Decodable, Equatable, Sendable {
    var events: [SurgeEvent]
    var logs: [LogEntry] { events.map(\.entry) }

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        let values =
            [
                value.array(for: "events"),
                value.array(for: "logs"),
                value.array(for: "items"),
                value.arrayValue,
            ]
            .first { !$0.isEmpty } ?? []
        events = values.enumerated().compactMap { index, value in
            Self.event(from: value, index: index)
        }
    }

    private static func event(
        from value: JSONValue,
        index: Int
    ) -> SurgeEvent? {
        if let message = value.stringValue {
            return SurgeEvent(
                identity: "\(index):\(message)",
                entry: LogEntry(type: "info", payload: message)
            )
        }
        guard case .object = value else { return nil }
        let payload =
            value.string(
                for: "message",
                "payload",
                "content",
                "title",
                "event"
            ) ?? value.prettyJSONText
        let type = logType(from: value, payload: payload)
        let date = value.string(for: "date", "timestamp", "time") ?? ""
        let identity =
            value.string(for: "identifier", "id")
            ?? "\(date):\(type):\(payload)"
        return SurgeEvent(
            identity: identity,
            entry: LogEntry(type: type, payload: payload)
        )
    }

    private static func logType(
        from value: JSONValue,
        payload: String
    ) -> String {
        if let numericType = value.int(for: "type") {
            return normalizedNumericType(numericType, payload: payload)
        }
        if let rawType = value.string(
            for: "level",
            "category",
            "severity",
            "type"
        ) {
            return normalizedTextType(rawType, payload: payload)
        }
        return inferredType(from: payload)
    }

    private static func normalizedNumericType(
        _ type: Int,
        payload: String
    ) -> String {
        switch type {
        case ..<1:
            return inferredType(from: payload)
        case 1:
            return "warning"
        default:
            return "error"
        }
    }

    private static func normalizedTextType(
        _ type: String,
        payload: String
    ) -> String {
        switch type.lowercased() {
        case "verbose", "debug":
            return "debug"
        case "warn", "warning":
            return "warning"
        case "error", "fault", "critical":
            return "error"
        case "info", "notice", "notify":
            return "info"
        default:
            return inferredType(from: payload)
        }
    }

    private static func inferredType(from payload: String) -> String {
        let lowercased = payload.lowercased()
        if lowercased.contains("error")
            || lowercased.contains("failed")
            || lowercased.contains("failure") {
            return "error"
        }
        if lowercased.contains("warn") {
            return "warning"
        }
        if lowercased.contains("debug")
            || lowercased.contains("verbose") {
            return "debug"
        }
        return "info"
    }
}
