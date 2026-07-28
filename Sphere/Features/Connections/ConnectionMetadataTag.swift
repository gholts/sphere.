import SwiftUI

struct ConnectionMetadataTag: View {
    var value: String?
    var fallback: String

    var body: some View {
        Text(verbatim: normalizedValue.backendNameForDisplay)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    private var normalizedValue: String {
        let trimmed =
            value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
