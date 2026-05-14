import SwiftUI

struct RuleView: View {
    @EnvironmentObject private var app: AppModel
    @State private var refreshingRuleSetNames: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section("Rules") {
                    if app.rules.isEmpty {
                        EmptyStateView(title: "No Rules", message: "Backend returned no rule data.", systemImage: "list.bullet.rectangle")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(app.rules) { rule in
                            RuleRow(
                                rule: rule,
                                provider: provider(for: rule),
                                isRefreshing: refreshingRuleSetNames.contains(rule.payload),
                                refresh: { refreshRuleSet(rule.payload) }
                            )
                        }
                    }
                }
            }
            .backendPageToolbar(tab: .rule)
            .refreshable {
                await app.refreshRules(source: .pullToRefresh)
            }
        }
    }

    private func provider(for rule: RuleItem) -> RuleProvider? {
        guard rule.isRuleSet else { return nil }
        return app.ruleProviders.first { $0.name == rule.payload }
    }

    private func refreshRuleSet(_ name: String) {
        guard !refreshingRuleSetNames.contains(name) else { return }
        refreshingRuleSetNames.insert(name)
        Task {
            await app.refreshRuleProvider(name)
            await MainActor.run {
                _ = refreshingRuleSetNames.remove(name)
            }
        }
    }
}

private struct RuleRow: View {
    var rule: RuleItem
    var provider: RuleProvider?
    var isRefreshing: Bool
    var refresh: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.displayTitle)
                    .lineLimit(2)
                metadataRow
            }
            Spacer()
            if provider?.isRemote == true {
                Button(action: refresh) {
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .opacity(isRefreshing ? 0 : 1)
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    }
                    .frame(width: 24, height: 24)
                    .animation(.smooth(duration: 0.22), value: isRefreshing)
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh \(rule.payload)")
            }
        }
    }

    @ViewBuilder
    private var metadataRow: some View {
        if rule.isMatch {
            Text(rule.proxy)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack {
                Text(rule.type)
                if let provider {
                    Text(provider.behavior ?? provider.vehicleType ?? provider.type ?? "Provider")
                }
                if let count = provider?.ruleCount {
                    Text("\(count) rules")
                }
                Spacer()
                Text(rule.proxy)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
