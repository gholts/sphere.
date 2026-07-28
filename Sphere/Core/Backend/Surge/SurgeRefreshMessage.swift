import Foundation

nonisolated enum SurgeRefreshMessage {
    private static let successMessage = "Policy group refresh requested."

    static func message(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            let message =
                value.trimmedString(for: "message", "detail", "error", "reason", "description")
                ?? statusMessage(from: value)
                ?? reloadOutcomeMessage(from: value)
                ?? value.trimmedScalarString
            guard let message else { return nil }
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let text = String(bytes: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }
        return text.isEmpty ? nil : text
    }

    private static func statusMessage(from value: JSONValue) -> String? {
        guard let status = value.trimmedString(for: "status", "result") else { return nil }
        switch status.lowercased() {
        case "ok", "success", "succeeded", "successful":
            return successMessage
        default:
            return "Surge profile reload status: \(status)"
        }
    }

    private static func reloadOutcomeMessage(from value: JSONValue) -> String? {
        guard let success = value.bool(for: "success", "ok", "result") else { return nil }
        return success ? successMessage : "Policy group refresh failed. Surge reported failure."
    }
}
