import Foundation

nonisolated final class SourceIPTagStore {
    var tags: [SourceIPTag] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        load()
    }

    func tag(for sourceIP: String?) -> String? {
        guard let normalizedSourceIP = Self.normalized(sourceIP) else { return nil }
        return tags.first { $0.sourceIP == normalizedSourceIP }?.tag
    }

    func setTag(_ tag: String, for sourceIP: String) {
        guard let normalizedSourceIP = Self.normalized(sourceIP) else { return }
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedTag.isEmpty {
            removeTag(for: normalizedSourceIP)
            return
        }

        if let index = tags.firstIndex(where: { $0.sourceIP == normalizedSourceIP }) {
            guard tags[index].tag != normalizedTag else { return }
            tags[index].tag = normalizedTag
        } else {
            tags.append(SourceIPTag(sourceIP: normalizedSourceIP, tag: normalizedTag))
        }
        save()
    }

    func removeTag(for sourceIP: String) {
        guard let normalizedSourceIP = Self.normalized(sourceIP) else { return }
        let count = tags.count
        tags.removeAll { $0.sourceIP == normalizedSourceIP }
        if tags.count != count {
            save()
        }
    }

    func currentSourceIPs(from connections: [ConnectionInfo]) -> [String] {
        let connectionIPs = connections.compactMap { Self.normalized($0.metadata.sourceIP) }
        let taggedIPs = tags.compactMap { Self.normalized($0.sourceIP) }
        return Array(Set(connectionIPs + taggedIPs))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func load() {
        guard let data = defaults.data(forKey: AppStorageKeys.sourceIPTags),
            let decodedTags = try? JSONDecoder().decode([SourceIPTag].self, from: data)
        else {
            tags = []
            return
        }
        tags = deduplicated(decodedTags)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tags) else { return }
        defaults.set(data, forKey: AppStorageKeys.sourceIPTags)
    }

    private func deduplicated(_ tags: [SourceIPTag]) -> [SourceIPTag] {
        var seen: Set<String> = []
        var output: [SourceIPTag] = []
        for tag in tags {
            guard let normalizedSourceIP = Self.normalized(tag.sourceIP),
                let label = Self.normalized(tag.tag),
                !seen.contains(normalizedSourceIP)
            else {
                continue
            }
            seen.insert(normalizedSourceIP)
            output.append(SourceIPTag(id: tag.id, sourceIP: normalizedSourceIP, tag: label))
        }
        return output
    }

    nonisolated static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
