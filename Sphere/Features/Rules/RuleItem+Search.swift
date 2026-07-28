import Foundation

extension RuleItem {
    nonisolated func matches(searchQuery: String, provider: RuleProvider?) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let values = [
            displayTitle,
            type,
            payload,
            proxy,
            provider?.name,
            provider?.behavior,
            provider?.vehicleType,
            provider?.type,
            provider?.ruleCount.map(String.init),
        ]
        return values.compactMap(\.self).contains { value in
            value.localizedStandardContains(query)
        }
    }
}
