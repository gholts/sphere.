import Foundation

@MainActor
extension AppModel {
    func refreshRuleProvider(_ name: String) async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.refreshRuleProvider(name)
            rules = try await client.rules()
            ruleProviders = try await client.ruleProviders()
            applyConfigs(try await client.configs())
            saveCachedDataIfUseful()
        }
    }
}
