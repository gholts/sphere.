import Foundation

@MainActor
extension AppModel {
    func sourceIPTag(for sourceIP: String?) -> String? {
        guard selectedProfile?.kind.supportsSourceIPTags == true else { return nil }
        guard let normalizedSourceIP = SourceIPTagStore.normalized(sourceIP) else { return nil }
        return sourceIPTags.first { $0.sourceIP == normalizedSourceIP }?.tag
    }

    func setSourceIPTag(_ tag: String, for sourceIP: String) {
        guard selectedProfile?.kind.supportsSourceIPTags == true else { return }
        sourceIPTagStore.setTag(tag, for: sourceIP)
        sourceIPTags = sourceIPTagStore.tags
    }

    func removeSourceIPTag(for sourceIP: String) {
        guard selectedProfile?.kind.supportsSourceIPTags == true else { return }
        sourceIPTagStore.removeTag(for: sourceIP)
        sourceIPTags = sourceIPTagStore.tags
    }

    func currentSourceIPs(from connections: [ConnectionInfo]) -> [String] {
        guard selectedProfile?.kind.supportsSourceIPTags == true else { return [] }
        return sourceIPTagStore.currentSourceIPs(from: connections)
    }
}
