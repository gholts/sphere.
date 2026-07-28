import SwiftUI

struct RuleRow: View {
    var rule: RuleItem
    var provider: RuleProvider?
    var isRefreshing: Bool
    var refresh: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.displayTitle)
                    .lineLimit(2)
                RuleMetadataRow(rule: rule, provider: provider)
            }
            Spacer()
            if provider?.isRemote == true {
                Button(action: refresh) {
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .opacity(isRefreshing ? 0 : 1)
                        if isRefreshing {
                            unsafe ProgressView()
                                .controlSize(.small)
                                .transition(
                                    .opacity.combined(
                                        with: .scale(scale: 0.92)
                                    )
                                )
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .animation(
                        .smooth(duration: 0.22),
                        value: isRefreshing
                    )
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh \(rule.payload)")
            }
        }
    }
}

private struct RuleMetadataRow: View {
    var rule: RuleItem
    var provider: RuleProvider?

    var body: some View {
        if rule.isMatch {
            Text(verbatim: rule.proxy.backendNameForDisplay)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack {
                Text(rule.type)
                if let provider {
                    Text(
                        provider.behavior
                            ?? provider.vehicleType
                            ?? provider.type
                            ?? "Provider"
                    )
                }
                if let count = provider?.ruleCount {
                    Text("\(count) rules")
                }
                Spacer()
                Text(verbatim: rule.proxy.backendNameForDisplay)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
