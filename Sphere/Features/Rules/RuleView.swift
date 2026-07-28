import SwiftUI

struct RuleView: View {
    @Environment(AppModel.self) private var app
    @State private var searchQuery = ""
    @State private var refreshingRuleSetNames: Set<String> = []

    var body: some View {
        NavigationStack {
            let providers = ruleProviderLookup
            let rules = filteredRules(providers: providers)
            List {
                Section("Rules") {
                    if app.rules.isEmpty {
                        EmptyStateView(
                            title: "No Rules", message: "Backend returned no rule data.",
                            systemImage: "list.bullet.rectangle"
                        )
                        .listRowBackground(Color.clear)
                    } else if rules.isEmpty {
                        ContentUnavailableView.search
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(rules) { rule in
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
            .scrollDismissesKeyboard(.interactively)
            .searchable(
                text: $searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search rules"
            )
            .backendPageToolbar(tab: .rule)
            .refreshable {
                await app.refreshRules(source: .pullToRefresh)
            }
        }
    }

    private var ruleProviderLookup: [String: RuleProvider] {
        Dictionary(
            app.ruleProviders.lazy.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func filteredRules(providers: [String: RuleProvider]) -> [RuleItem] {
        app.rules.filter { rule in
            rule.matches(
                searchQuery: searchQuery,
                provider: rule.isRuleSet ? providers[rule.payload] : nil
            )
        }
    }

    private func refreshRuleSet(_ name: String) {
        guard !refreshingRuleSetNames.contains(name) else { return }
        refreshingRuleSetNames.insert(name)
        Task {
            await app.refreshRuleProvider(name)
            refreshingRuleSetNames.remove(name)
        }
    }
}
