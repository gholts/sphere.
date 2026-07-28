import SwiftUI

struct ConnectionTrafficLine: View {
    var connection: ConnectionInfo

    var body: some View {
        HStack(spacing: 12) {
            ConnectionIconText(
                systemImage: "arrow.up",
                title: ByteFormat.bytes(connection.upload)
            )
            ConnectionIconText(
                systemImage: "arrow.down",
                title: ByteFormat.bytes(connection.download)
            )
            if let rule = normalizedRule {
                ConnectionIconText(
                    systemImage: "flag",
                    title: rule.backendNameForDisplay
                )
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var normalizedRule: String? {
        let rule =
            connection.rule?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
        return rule.isEmpty ? nil : rule
    }
}
