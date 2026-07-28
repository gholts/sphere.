import Foundation

extension SurgeClient {
    func rules() async throws -> [RuleItem] {
        try await api.get(.rules, query: [], as: SurgeRulesPayload.self).rules
    }

    func ruleProviders() -> [RuleProvider] {
        []
    }

    func refreshRuleProvider(_: String) {
        // Surge HTTP API has no rule provider refresh endpoint.
    }
}
