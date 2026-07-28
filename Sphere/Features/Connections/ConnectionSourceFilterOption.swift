import Foundation

struct ConnectionSourceFilterOption: Identifiable, Hashable {
    var id: String { value }
    var title: String
    var value: String
}

extension Array where Element == ConnectionSourceFilterOption {
    var stableUniqueSourceFilterOptions: [ConnectionSourceFilterOption] {
        var seen: Set<String> = []
        return filter { option in
            guard
                !option.value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            else {
                return false
            }
            return seen.insert(option.value).inserted
        }
    }
}
