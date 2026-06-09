import Foundation
import Observation

@Observable
@MainActor
final class ProxyStore {
    var proxyCollection = ProxyCollection()
    var proxyProviders: [ProxyProvider] = []
    var isTestingProxyGroupDelays = false
    var proxyGroupExpansionRevision = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var proxyLookup: [String: ProxyItem] = [:]
    @ObservationIgnored private var proxyGroupIcons: [String: String] = [:]
    @ObservationIgnored private var loadedProxyGroupIconsKey: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func reset() {
        proxyCollection = ProxyCollection()
        rebuildProxyLookup()
        proxyProviders = []
        proxyGroupIcons = [:]
        loadedProxyGroupIconsKey = nil
    }

    func proxyGroupExpandedKey(_ groupName: String, profileID: UUID?) -> String {
        "\(AppStorageKeys.proxyGroupExpandedPrefix).\(profileID?.uuidString ?? "none").\(groupName)"
    }

    func isProxyGroupExpanded(_ groupName: String, profileID: UUID?) -> Bool {
        let key = proxyGroupExpandedKey(groupName, profileID: profileID)
        guard let stored = defaults.object(forKey: key) as? Bool else { return false }
        return stored
    }

    func areAllProxyGroupsExpanded(_ groups: [ProxyItem], profileID: UUID?) -> Bool {
        !groups.isEmpty && groups.allSatisfy { isProxyGroupExpanded($0.name, profileID: profileID) }
    }

    func setProxyGroupExpanded(_ isExpanded: Bool, groupName: String, profileID: UUID?) {
        let key = proxyGroupExpandedKey(groupName, profileID: profileID)
        if let stored = defaults.object(forKey: key) as? Bool, stored == isExpanded {
            return
        }
        defaults.set(isExpanded, forKey: key)
        proxyGroupExpansionRevision &+= 1
    }

    func setAllProxyGroupsExpanded(_ isExpanded: Bool, groups: [ProxyItem], profileID: UUID?) {
        guard !groups.isEmpty else { return }
        for group in groups {
            defaults.set(
                isExpanded, forKey: proxyGroupExpandedKey(group.name, profileID: profileID))
        }
        proxyGroupExpansionRevision &+= 1
    }

    @discardableResult
    func setProxyCollection(_ collection: ProxyCollection, profileID: UUID?) -> Bool {
        let nextCollection = restoringCachedProxyGroupIcons(in: collection, profileID: profileID)
        guard proxyCollection != nextCollection else {
            return mergeProxyGroupIcons(from: nextCollection.groups, profileID: profileID)
        }
        proxyCollection = nextCollection
        rebuildProxyLookup()
        _ = mergeProxyGroupIcons(from: nextCollection.groups, profileID: profileID)
        return true
    }

    @discardableResult
    func setProxyProviders(_ providers: [ProxyProvider]) -> Bool {
        guard proxyProviders != providers else { return false }
        proxyProviders = providers
        return true
    }

    func proxyItem(named name: String) -> ProxyItem? {
        proxyLookup[name] ?? proxyCollection.item(named: name)
    }

    func rebuildProxyLookup() {
        let pairs = (proxyCollection.proxies + proxyCollection.groups).map { ($0.name, $0) }
        proxyLookup = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    func ensureProxyGroupIconsLoaded(profileID: UUID?) {
        let key = proxyGroupIconsKey(profileID: profileID)
        guard loadedProxyGroupIconsKey != key else { return }
        loadedProxyGroupIconsKey = key
        guard let data = defaults.data(forKey: key),
            let icons = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            proxyGroupIcons = [:]
            return
        }
        proxyGroupIcons = icons
    }

    func restoringCachedProxyGroupIcons(in collection: ProxyCollection, profileID: UUID?)
        -> ProxyCollection {
        ensureProxyGroupIconsLoaded(profileID: profileID)
        guard !proxyGroupIcons.isEmpty else { return collection }
        var next = collection
        var restoredIcon = false
        next.groups = collection.groups.map { group in
            guard group.icon?.isEmpty ?? true, let icon = proxyGroupIcons[group.name] else {
                return group
            }
            restoredIcon = true
            var copy = group
            copy.icon = icon
            return copy
        }
        return restoredIcon ? next : collection
    }

    func mergeProxyGroupIcons(from groups: [ProxyItem], profileID: UUID?) -> Bool {
        ensureProxyGroupIconsLoaded(profileID: profileID)
        var changed = false
        for group in groups {
            guard let icon = group.icon, !icon.isEmpty else { continue }
            if proxyGroupIcons[group.name] != icon {
                proxyGroupIcons[group.name] = icon
                changed = true
            }
        }
        guard changed else { return false }
        saveProxyGroupIcons(profileID: profileID)
        return true
    }

    func saveProxyGroupIcons(profileID: UUID?) {
        guard let data = try? JSONEncoder().encode(proxyGroupIcons) else { return }
        defaults.set(data, forKey: proxyGroupIconsKey(profileID: profileID))
    }

    func proxyGroupIconsKey(profileID: UUID?) -> String {
        "\(AppStorageKeys.proxyGroupIconsPrefix).\(profileID?.uuidString ?? "none")"
    }
}
