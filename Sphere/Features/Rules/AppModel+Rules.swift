import Foundation

@MainActor
extension AppModel {
    func refreshRuleProvider(_ name: String) async {
        guard let client else { return }
        await progressActivityReporter.start(
            kind: .ruleProvider,
            detail: name,
            fraction: ProgressActivityFractions.providerStarted
        )
        let outcome = await captureErrors {
            await progressActivityReporter.update(
                kind: .ruleProvider,
                detail: "Refreshing \(name)",
                fraction: ProgressActivityFractions.providerRefreshing
            )
            try await client.refreshRuleProvider(name)
            await progressActivityReporter.update(
                kind: .ruleProvider,
                detail: "Reloading rules",
                fraction: ProgressActivityFractions.providerReloading
            )
            rules = try await client.rules()
            ruleProviders = try await client.ruleProviders()
            applyConfigs(try await client.configs())
            saveCachedDataIfUseful()
        }
        if outcome.errorMessage == nil {
            await progressActivityReporter.finish(
                kind: .ruleProvider,
                status: .succeeded,
                detail: "Rule provider refreshed"
            )
        } else {
            await progressActivityReporter.finish(
                kind: .ruleProvider,
                status: .failed,
                detail: "Rule provider refresh failed"
            )
        }
    }
}
