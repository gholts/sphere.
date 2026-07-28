import SwiftUI

struct ConnectionSourceLabel: View {
    var sourceIP: String?
    var label: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "network")
                .accessibilityHidden(true)
            if let label {
                Text(verbatim: label.backendNameForDisplay)
                    .bold()
                    .lineLimit(1)
            } else {
                Text(verbatim: normalizedSourceIP)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private var normalizedSourceIP: String {
        let trimmed =
            sourceIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "source n/a" : trimmed
    }
}
