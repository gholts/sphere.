import Foundation
import Observation
import SwiftUI

nonisolated enum AppStorageKeys {
    static let profiles = "sphere.profiles"
    static let selectedProfileID = "sphere.selectedProfileID"
    static let proxyGroupExpandedPrefix = "sphere.proxyGroupExpanded"
    static let cachedDataPrefix = "sphere.cachedData"
    static let proxyGroupIconsPrefix = "sphere.proxyGroupIcons"
}

@Observable
@MainActor
final class ProfileStore {
    var profiles: [APIProfile] = []
    var selectedProfileID: UUID?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadProfiles()
    }

    nonisolated static func decode(_ data: Data) -> [APIProfile] {
        ProfileCodec.decode(data)
    }

    nonisolated static func encode(_ profiles: [APIProfile]) -> Data {
        ProfileCodec.encode(profiles)
    }

    var selectedProfile: APIProfile? {
        guard let selectedProfileID else {
            return profiles.first
        }
        return profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    var hasProfiles: Bool {
        !profiles.isEmpty
    }

    func loadProfiles() {
        let data = defaults.data(forKey: AppStorageKeys.profiles) ?? Data()
        profiles = Self.decode(data)
        if let storedID = defaults.string(forKey: AppStorageKeys.selectedProfileID).flatMap(UUID.init(uuidString:)) {
            selectedProfileID = storedID
        } else {
            selectedProfileID = profiles.first?.id
        }
    }

    func addProfile(_ profile: APIProfile) {
        profiles.append(profile)
        selectedProfileID = profile.id
        saveProfiles()
    }

    @discardableResult
    func updateProfile(_ profile: APIProfile) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            addProfile(profile)
            return true
        }
        let oldProfile = profiles[index]
        let wasSelected = selectedProfile?.id == profile.id
        profiles[index] = profile
        if wasSelected {
            selectedProfileID = profile.id
        }
        saveProfiles()
        return wasSelected && (oldProfile.kind != profile.kind || oldProfile.baseURL != profile.baseURL)
    }

    @discardableResult
    func deleteProfiles(at offsets: IndexSet) -> Bool {
        let previousSelectedProfileID = selectedProfileID
        profiles.remove(atOffsets: offsets)
        if !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profiles.first?.id
        }
        saveProfiles()
        return selectedProfileID != previousSelectedProfileID
    }

    @discardableResult
    func deleteProfile(_ profile: APIProfile) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return false }
        return deleteProfiles(at: IndexSet(integer: index))
    }

    func moveProfiles(from offsets: IndexSet, to destination: Int) {
        profiles.move(fromOffsets: offsets, toOffset: destination)
        saveProfiles()
    }

    @discardableResult
    func selectProfile(_ id: UUID?) -> Bool {
        guard selectedProfileID != id else { return false }
        selectedProfileID = id
        defaults.set(id?.uuidString, forKey: AppStorageKeys.selectedProfileID)
        return true
    }

    func saveProfiles() {
        defaults.set(Self.encode(profiles), forKey: AppStorageKeys.profiles)
        defaults.set(selectedProfileID?.uuidString, forKey: AppStorageKeys.selectedProfileID)
    }
}

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
        guard let stored = defaults.object(forKey: key) as? Bool else { return true }
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
            defaults.set(isExpanded, forKey: proxyGroupExpandedKey(group.name, profileID: profileID))
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

    func restoringCachedProxyGroupIcons(in collection: ProxyCollection, profileID: UUID?) -> ProxyCollection {
        ensureProxyGroupIconsLoaded(profileID: profileID)
        guard !proxyGroupIcons.isEmpty else { return collection }
        var next = collection
        var restoredIcon = false
        next.groups = collection.groups.map { group in
            guard group.icon?.isEmpty ?? true, let icon = proxyGroupIcons[group.name] else { return group }
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

@Observable
@MainActor
final class ConfigStore {
    var rules: [RuleItem] = []
    var ruleProviders: [RuleProvider] = []
    var configs: [String: JSONValue] = [:]
    var clashMode: ClashMode = .rule

    func reset() {
        rules = []
        ruleProviders = []
        configs = [:]
        clashMode = .rule
    }

    func applyConfigs(_ values: [String: JSONValue]) {
        configs = values
        if case .string(let mode)? = values["mode"],
           let decodedMode = ClashMode(mihomoValue: mode) {
            clashMode = decodedMode
        }
    }
}

@Observable
@MainActor
final class LiveState {
    var overview = BackendOverview.empty
    var connections = ConnectionsSnapshot(uploadTotal: nil, downloadTotal: nil, connections: [])
    var logs: [LogEntry] = []
    var logLevel: LogLevel = .info

    func resetBackendData() {
        overview = .empty
        connections = ConnectionsSnapshot(uploadTotal: nil, downloadTotal: nil, connections: [])
    }

    func resetLogs() {
        logs = []
        logLevel = .info
    }

    func reset() {
        resetBackendData()
        resetLogs()
    }
}
