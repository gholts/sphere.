import SwiftUI

struct ConnectionProxySelector: View {
    var groups: [ProxyItem]
    var proxyItem: (String) -> ProxyItem?
    var selectProxy: (String, String) -> Void

    var body: some View {
        Menu {
            ForEach(groups) { group in
                Section {
                    ForEach(group.all, id: \.self) { proxyName in
                        Button {
                            selectProxy(group.name, proxyName)
                        } label: {
                            ConnectionProxyOptionLabel(
                                proxyName: proxyName,
                                selectedProxyName: group.now,
                                displayName: proxyItem(proxyName)?.displayName
                                    ?? proxyName.backendNameForDisplay
                            )
                        }
                    }
                } header: {
                    Text(verbatim: group.displayName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .accessibilityHidden(true)
                Text(verbatim: selectionSummary)
                    .lineLimit(1)
            }
            .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel("Select proxy")
        .accessibilityValue(selectionSummary)
    }

    private var selectionSummary: String {
        guard groups.count == 1, let group = groups.first else {
            return "\(groups.count) proxy groups"
        }
        let selected = group.now.flatMap {
            proxyItem($0)?.displayName ?? $0.backendNameForDisplay
        }
        return "\(group.displayName): \(selected ?? "none")"
    }
}

private struct ConnectionProxyOptionLabel: View {
    var proxyName: String
    var selectedProxyName: String?
    var displayName: String

    var body: some View {
        if proxyName == selectedProxyName {
            Label {
                Text(verbatim: displayName)
            } icon: {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
        } else {
            Text(verbatim: displayName)
        }
    }
}
