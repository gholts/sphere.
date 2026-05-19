import SwiftUI

struct RuleView: View {
    @Environment(AppModel.self) private var app
    @State private var refreshingRuleSetNames: Set<String> = []
    
    var body: some View {
        NavigationStack {
            let providers = ruleProviderLookup
            List {
                Section("Rules") {
                    if app.rules.isEmpty {
                        EmptyStateView(title: "No Rules", message: "Backend returned no rule data.", systemImage: "list.bullet.rectangle")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(app.rules) { rule in
                            RuleRow(
                                rule: rule,
                                provider: rule.isRuleSet ? providers[rule.payload] : nil,
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
    
    private var ruleProviderLookup: [String: RuleProvider] {
        Dictionary(app.ruleProviders.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
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
                RuleMetadataRow(rule: rule, provider: provider)
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
                    Text(provider.behavior ?? provider.vehicleType ?? provider.type ?? "Provider")
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
