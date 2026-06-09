import Foundation

@MainActor
extension AppModel {
    func sourceIPTag(for sourceIP: String?) -> String? {
        guard let normalizedSourceIP = SourceIPTagStore.normalized(sourceIP) else { return nil }
        return sourceIPTags.first { $0.sourceIP == normalizedSourceIP }?.tag
    }

    func setSourceIPTag(_ tag: String, for sourceIP: String) {
        sourceIPTagStore.setTag(tag, for: sourceIP)
        sourceIPTags = sourceIPTagStore.tags
    }

    func removeSourceIPTag(for sourceIP: String) {
        sourceIPTagStore.removeTag(for: sourceIP)
        sourceIPTags = sourceIPTagStore.tags
    }

    func currentSourceIPs(from connections: [ConnectionInfo]) -> [String] {
        let connectionIPs = connections.compactMap {
            SourceIPTagStore.normalized($0.metadata.sourceIP)
        }
        let taggedIPs = sourceIPTags.compactMap { SourceIPTagStore.normalized($0.sourceIP) }
        return Array(Set(connectionIPs + taggedIPs))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
