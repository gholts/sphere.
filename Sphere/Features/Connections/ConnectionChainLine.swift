import SwiftUI

struct ConnectionChainLine: View {
    var connection: ConnectionInfo

    var body: some View {
        let chains = connection.displayChains
        let displayedChains = chains.prefix(3)
        if displayedChains.isEmpty {
            Label(
                "outbound n/a",
                systemImage: "arrow.triangle.branch"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                ForEach(displayedChains.indices, id: \.self) { index in
                    Text(
                        verbatim:
                            displayedChains[index].backendNameForDisplay
                    )
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color.accentColor.opacity(0.1),
                        in: Capsule()
                    )
                }
                if chains.count > displayedChains.count {
                    Text("+\(chains.count - displayedChains.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
