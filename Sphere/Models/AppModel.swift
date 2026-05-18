import Combine
import Foundation
import SwiftUI

enum RefreshSource {
    case manual
    case automatic
    case pullToRefresh

    var isUserInitiated: Bool {
        self != .automatic
    }

    var waitsForBackendErrorDebounce: Bool {
        self == .pullToRefresh
    }
}

struct RefreshOutcome {
    var connectionFailed = false
    var backendConnected = false
    var errorMessage: String?

    init() {}

    init(error: Error) {
        guard !error.isCancellation else { return }
        connectionFailed = error.isConnectionFailure
        errorMessage = error.localizedDescription
    }

    mutating func merge(_ other: Self) {
        connectionFailed = connectionFailed || other.connectionFailed
        backendConnected = backendConnected || other.backendConnected
        errorMessage = other.errorMessage ?? errorMessage
    }

    mutating func markBackendConnected() {
        backendConnected = true
    }
}

extension Error {
    var isCancellation: Bool {
        if self is CancellationError { return true }
        return (self as? URLError)?.code == .cancelled
    }

    var isConnectionFailure: Bool {
        guard let error = self as? URLError else { return false }
        switch error.code {
        case .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .secureConnectionFailed,
             .serverCertificateUntrusted:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class LiveBackendStore: ObservableObject {
    @Published var overview = BackendOverview.empty
    @Published var connections = ConnectionsSnapshot(uploadTotal: nil, downloadTotal: nil, connections: [])

    func reset() {
        overview = .empty
        connections = ConnectionsSnapshot(uploadTotal: nil, downloadTotal: nil, connections: [])
    }
}

@MainActor
final class LogStore: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var level: LogLevel = .info

    func reset() {
        entries = []
        level = .info
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [APIProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var selectedTab: AppTab = .proxies
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var proxyCollection = ProxyCollection()
    @Published var proxyProviders: [ProxyProvider] = []
    @Published var rules: [RuleItem] = []
    @Published var ruleProviders: [RuleProvider] = []
    @Published var configs: [String: JSONValue] = [:]
    @Published var clashMode: ClashMode = .rule
    @Published var isUpdatingCore = false
    @Published var isAutoRefreshSuspended = false
    @Published var isBackendErrorDebouncing = false
    @Published var isManualRefreshActive = false
    @Published var toolbarRefreshingTabs: Set<AppTab> = []
    @Published private(set) var isTestingProxyGroupDelays = false
    @Published private(set) var proxyGroupExpansionRevision = 0

    let liveStore = LiveBackendStore()
    let logStore = LogStore()

    let defaults: UserDefaults
    private let makeClient: @MainActor (APIProfile) -> any ProxyBackendClient
    private let progressActivityReporter: any ProgressActivityReporting
    let backendErrorDebounceDuration: Duration
    var connectionTask: Task<Void, Never>?
    var memoryTask: Task<Void, Never>?
    var trafficTask: Task<Void, Never>?
    var logTask: Task<Void, Never>?
    var autoRefreshTask: Task<Void, Never>?
    var backendErrorTask: Task<Void, Never>?
    var cacheSaveTask: Task<Void, Never>?
    var backendSuccessGeneration = 0
    var manualRefreshDepth = 0
    var pendingBackendErrorMessage: String?
    var lastCacheSave = Date.distantPast
    var proxyLookup: [String: ProxyItem] = [:]
    var proxyGroupIcons: [String: String] = [:]
    var loadedProxyGroupIconsKey: String?
    let cacheSaveInterval: TimeInterval = 5

    enum Keys {
        static let profiles = "sphere.profiles"
        static let selectedProfileID = "sphere.selectedProfileID"
        static let proxyGroupExpandedPrefix = "sphere.proxyGroupExpanded"
        static let cachedDataPrefix = "sphere.cachedData"
        static let proxyGroupIconsPrefix = "sphere.proxyGroupIcons"
    }

    init(
        defaults: UserDefaults = .standard,
        backendErrorDebounceDuration: Duration = .seconds(5),
        progressActivityReporter: (any ProgressActivityReporting)? = nil,
        clientFactory: @escaping @MainActor (APIProfile) -> any ProxyBackendClient = BackendClientFactory.make(profile:)
    ) {
        self.defaults = defaults
        self.backendErrorDebounceDuration = backendErrorDebounceDuration
        self.progressActivityReporter = progressActivityReporter ?? ProgressActivityReporterFactory.makeDefault()
        self.makeClient = clientFactory
        loadProfiles()
        loadCachedData()
    }

    deinit {
        connectionTask?.cancel()
        memoryTask?.cancel()
        trafficTask?.cancel()
        logTask?.cancel()
        autoRefreshTask?.cancel()
        backendErrorTask?.cancel()
        cacheSaveTask?.cancel()
    }

    var overview: BackendOverview {
        get { liveStore.overview }
        set { liveStore.overview = newValue }
    }

    var connections: ConnectionsSnapshot {
        get { liveStore.connections }
        set { liveStore.connections = newValue }
    }

    var logs: [LogEntry] {
        get { logStore.entries }
        set { logStore.entries = newValue }
    }

    var logLevel: LogLevel {
        get { logStore.level }
        set { logStore.level = newValue }
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

    var client: (any ProxyBackendClient)? {
        selectedProfile.map(makeClient)
    }

    var canUpdateCore: Bool {
        selectedProfile?.kind == .mihomo && !overview.version.localizedCaseInsensitiveContains("sing-box")
    }

    var visibleBackendErrorMessage: String? {
        isManualRefreshActive ? nil : errorMessage
    }

    var showsBackendErrorSpinner: Bool {
        isBackendErrorDebouncing && !isManualRefreshActive
    }

    func loadProfiles() {
        let data = defaults.data(forKey: Keys.profiles) ?? Data()
        profiles = ProfileStore.decode(data)
        if let storedID = defaults.string(forKey: Keys.selectedProfileID).flatMap(UUID.init(uuidString:)) {
            selectedProfileID = storedID
        } else {
            selectedProfileID = profiles.first?.id
        }
    }

    func addProfile(_ profile: APIProfile) {
        profiles.append(profile)
        selectedProfileID = profile.id
        saveProfiles()
        selectedTab = .proxies
    }

    func updateProfile(_ profile: APIProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            addProfile(profile)
            return
        }
        let oldProfile = profiles[index]
        let wasSelected = selectedProfile?.id == profile.id
        profiles[index] = profile
        if wasSelected {
            selectedProfileID = profile.id
        }
        saveProfiles()

        guard wasSelected else { return }
        if oldProfile.kind != profile.kind || oldProfile.baseURL != profile.baseURL {
            defaults.removeObject(forKey: cacheKey(profileID: profile.id))
            resetLoadedData()
        }
    }

    func deleteProfiles(at offsets: IndexSet) {
        let previousSelectedProfileID = selectedProfileID
        profiles.remove(atOffsets: offsets)
        if !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profiles.first?.id
        }
        saveProfiles()
        if selectedProfileID != previousSelectedProfileID {
            resetLoadedData()
            loadCachedData()
        }
    }

    func deleteProfile(_ profile: APIProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        deleteProfiles(at: IndexSet(integer: index))
    }

    func moveProfiles(from offsets: IndexSet, to destination: Int) {
        profiles.move(fromOffsets: offsets, toOffset: destination)
        saveProfiles()
    }

    func selectProfile(_ id: UUID?) {
        selectedProfileID = id
        defaults.set(id?.uuidString, forKey: Keys.selectedProfileID)
        resetLoadedData()
        loadCachedData()
    }

    func saveProfiles() {
        defaults.set(ProfileStore.encode(profiles), forKey: Keys.profiles)
        defaults.set(selectedProfileID?.uuidString, forKey: Keys.selectedProfileID)
    }

    func testProfile(_ profile: APIProfile) async throws -> BackendOverview {
        try await makeClient(profile).testConnection()
    }

    func refreshAll(source: RefreshSource = .manual) async {
        guard let client else { return }
        prepareRefresh(source: source)
        isLoading = true
        defer { isLoading = false }

        async let versionValue = result { try await client.version() }
        async let overviewValue = result { try await client.overview() }
        async let proxiesValue = result { try await client.proxies() }
        async let providersValue = result { try await client.proxyProviders() }
        async let rulesValue = result { try await client.rules() }
        async let ruleProvidersValue = result { try await client.ruleProviders() }
        async let configValue = result { try await client.configs() }
        async let modeValue = result { try await client.clashMode() }

        var outcome = RefreshOutcome()
        outcome.merge(apply(await overviewValue) { applyOverviewStats($0) })
        outcome.merge(apply(await versionValue) { applyVersion($0) })
        outcome.merge(apply(await proxiesValue) { setProxyCollection($0) })
        outcome.merge(apply(await providersValue) { proxyProviders = $0 })
        outcome.merge(apply(await rulesValue) { rules = $0 })
        outcome.merge(apply(await ruleProvidersValue) { ruleProviders = $0 })
        outcome.merge(apply(await configValue) { applyConfigs($0) })
        outcome.merge(apply(await modeValue) { clashMode = $0 })
        saveCachedDataIfUseful()
        await finishRefresh(outcome, source: source)
    }

    func startAutoRefresh() {
        guard !isAutoRefreshSuspended else { return }
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await self?.refreshSelectedTab(source: .automatic)
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func refreshSelectedTab(source: RefreshSource = .manual) async {
        if source == .automatic, isAutoRefreshSuspended {
            return
        }
        await refresh(tab: selectedTab, source: source)
    }

    func refreshFromToolbar(_ tab: AppTab) async {
        guard !toolbarRefreshingTabs.contains(tab) else { return }
        toolbarRefreshingTabs.insert(tab)
        defer { toolbarRefreshingTabs.remove(tab) }
        await refresh(tab: tab, source: .manual)
    }

    func isToolbarRefreshing(_ tab: AppTab) -> Bool {
        toolbarRefreshingTabs.contains(tab)
    }

    private func refresh(tab: AppTab, source: RefreshSource) async {
        switch tab {
        case .proxies:
            await refreshProxies(source: source)
        case .rule:
            await refreshRules(source: source)
        case .connections:
            await refreshConnections(source: source)
        case .more:
            await refreshAll(source: source)
        }
    }

    func refreshProxies(source: RefreshSource = .manual) async {
        guard let client else { return }
        prepareRefresh(source: source)

        async let proxyValue = result { try await client.proxies() }
        async let providerValue = result { try await client.proxyProviders() }

        var outcome = RefreshOutcome()
        var didChange = false

        switch await proxyValue {
        case .success(let collection):
            didChange = setProxyCollection(collection) || didChange
            outcome.markBackendConnected()
        case .failure(let error):
            outcome.merge(RefreshOutcome(error: error))
        }

        switch await providerValue {
        case .success(let providers):
            didChange = setProxyProviders(providers) || didChange
            outcome.markBackendConnected()
        case .failure(let error):
            outcome.merge(RefreshOutcome(error: error))
        }

        if didChange {
            saveCachedDataIfUseful()
        }
        await finishRefresh(outcome, source: source)
    }

    func refreshRules(source: RefreshSource = .manual) async {
        guard let client else { return }
        prepareRefresh(source: source)
        async let rulesValue = result { try await client.rules() }
        async let ruleProvidersValue = result { try await client.ruleProviders() }
        async let configValue = result { try await client.configs() }

        var outcome = RefreshOutcome()
        outcome.merge(apply(await rulesValue) { rules = $0 })
        outcome.merge(apply(await ruleProvidersValue) { ruleProviders = $0 })
        outcome.merge(apply(await configValue) { applyConfigs($0) })
        if outcome.backendConnected {
            saveCachedDataIfUseful()
        }
        await finishRefresh(outcome, source: source)
    }

    func selectProxy(group: String, proxy: String) async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.selectProxy(group: group, proxy: proxy)
            setProxyCollection(try await client.proxies())
            saveCachedDataIfUseful()
        }
    }

    func refreshProxyProvider(_ name: String) async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.refreshProxyProvider(name)
            proxyProviders = try await client.proxyProviders()
            saveCachedDataIfUseful()
        }
    }

    func testProxyGroupDelays() async {
        guard let client, !isTestingProxyGroupDelays else { return }
        let groupNames = proxyCollection.groups.map(\.name)
        guard !groupNames.isEmpty else { return }

        isTestingProxyGroupDelays = true
        defer { isTestingProxyGroupDelays = false }

        await progressActivityReporter.start(
            kind: .latencyTest,
            detail: "0/\(groupNames.count) groups",
            fraction: 0
        )

        let outcome = await captureErrors {
            var didChange = false
            let delays = try await delayProxyGroups(client: client, groupNames: groupNames) { completed, total in
                await self.progressActivityReporter.update(
                    kind: .latencyTest,
                    detail: "\(completed)/\(total) groups",
                    fraction: Double(completed) / Double(total) * ProgressActivityFractions.latencyGroupTestingWeight
                )
            }
            if !delays.isEmpty {
                didChange = setProxyCollection(proxyCollection.applyingDelayResults(delays)) || didChange
            }
            await progressActivityReporter.update(
                kind: .latencyTest,
                detail: "Refreshing nodes",
                fraction: ProgressActivityFractions.latencyRefreshing
            )
            let proxyRefresh = await result { try await client.proxies() }
            switch proxyRefresh {
            case .success(let collection):
                didChange = setProxyCollection(collection) || didChange
            case .failure(let error):
                if delays.isEmpty {
                    throw error
                }
            }
            if didChange {
                saveCachedDataIfUseful()
            }
        }

        if outcome.errorMessage == nil {
            await progressActivityReporter.finish(
                kind: .latencyTest,
                status: .succeeded,
                detail: "Latency test finished"
            )
        } else {
            await progressActivityReporter.finish(
                kind: .latencyTest,
                status: .failed,
                detail: "Latency test failed"
            )
        }
    }

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

    func loadConfig() async {
        guard let client else { return }
        _ = await captureErrors {
            applyConfigs(try await client.configs())
            saveCachedDataIfUseful()
        }
    }

    func patchConfig(_ changedValues: [String: JSONValue]) async -> Bool {
        guard let client else { return false }
        let outcome = await captureErrors {
            try await client.patchConfigs(changedValues)
            applyConfigs(try await client.configs())
            saveCachedDataIfUseful()
        }
        return outcome.errorMessage == nil
    }

    func reloadConfig() async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.reloadConfig()
            applyConfigs(try await client.configs())
            saveCachedDataIfUseful()
        }
    }

    func updateMode(_ mode: ClashMode) async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.updateClashMode(mode)
            clashMode = mode
            applyConfigs(try await client.configs())
            saveCachedDataIfUseful()
        }
    }

    func refreshConnections(source: RefreshSource = .manual) async {
        guard let client else { return }
        prepareRefresh(source: source)
        let outcome = await captureErrors {
            updateConnections(try await client.connections())
            saveCachedDataIfUseful()
        }
        await finishRefresh(outcome, source: source)
    }

    func closeConnection(_ id: String) async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.closeConnection(id)
            updateConnections(try await client.connections())
            saveCachedDataIfUseful()
        }
    }

    func closeAllConnections() async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.closeAllConnections()
            updateConnections(try await client.connections())
            saveCachedDataIfUseful()
        }
    }

    func upgradeCore(channel: CoreUpdateChannel) async -> CoreUpdateReport {
        guard let client, canUpdateCore else {
            return .skipped(channel: channel)
        }
        isUpdatingCore = true
        defer { isUpdatingCore = false }
        await progressActivityReporter.start(
            kind: .coreUpdate,
            detail: "\(channel.title) channel",
            fraction: ProgressActivityFractions.coreStarted
        )
        do {
            await progressActivityReporter.update(
                kind: .coreUpdate,
                detail: "Downloading \(channel.title.lowercased()) core",
                fraction: ProgressActivityFractions.coreDownloading
            )
            try await client.upgradeCore(channel: channel)
            markBackendConnected()
            await progressActivityReporter.update(
                kind: .coreUpdate,
                detail: "Refreshing backend data",
                fraction: ProgressActivityFractions.coreRefreshing
            )
            await refreshAll()
            await progressActivityReporter.finish(
                kind: .coreUpdate,
                status: .succeeded,
                detail: "Core update finished"
            )
            return .success(channel: channel)
        } catch {
            guard !error.isCancellation else {
                await progressActivityReporter.finish(
                    kind: .coreUpdate,
                    status: .failed,
                    detail: "Core update cancelled"
                )
                return .failure(channel: channel, message: "Cancelled.")
            }
            beginBackendErrorDebounce(error.localizedDescription)
            await progressActivityReporter.finish(
                kind: .coreUpdate,
                status: .failed,
                detail: "Core update failed"
            )
            return .failure(channel: channel, message: error.localizedDescription)
        }
    }

    func startLiveStreams() {
        switch selectedTab {
        case .connections:
            startConnectionStream()
            stopOverviewStreams()
        case .more:
            startConnectionStream()
            startMemoryStream()
            startTrafficStream()
        case .proxies, .rule:
            stopLiveStreams()
        }
    }

    func stopLiveStreams() {
        stopConnectionStream()
        stopOverviewStreams()
    }

    private func stopOverviewStreams() {
        stopMemoryStream()
        stopTrafficStream()
        flushPendingCacheSave()
    }

    func isProxyGroupExpanded(_ groupName: String) -> Bool {
        let key = proxyGroupExpandedKey(groupName)
        guard let stored = defaults.object(forKey: key) as? Bool else { return true }
        return stored
    }

    func areAllProxyGroupsExpanded(_ groups: [ProxyItem]) -> Bool {
        !groups.isEmpty && groups.allSatisfy { isProxyGroupExpanded($0.name) }
    }

    func setProxyGroupExpanded(_ isExpanded: Bool, groupName: String) {
        let key = proxyGroupExpandedKey(groupName)
        if let stored = defaults.object(forKey: key) as? Bool, stored == isExpanded {
            return
        }
        defaults.set(isExpanded, forKey: key)
        proxyGroupExpansionRevision &+= 1
    }

    func setAllProxyGroupsExpanded(_ isExpanded: Bool, groups: [ProxyItem]) {
        guard !groups.isEmpty else { return }
        for group in groups {
            defaults.set(isExpanded, forKey: proxyGroupExpandedKey(group.name))
        }
        proxyGroupExpansionRevision &+= 1
    }

    func startConnectionStream() {
        connectionTask?.cancel()
        guard let client else { return }
        connectionTask = Task { [weak self] in
            do {
                for try await snapshot in client.connectionEvents(interval: 1000) {
                    guard let self else { return }
                    markBackendConnected()
                    updateConnections(snapshot)
                }
            } catch where error.isCancellation || Task.isCancelled {
                return
            } catch {
                await self?.pollConnections(client: client)
            }
        }
    }

    func stopConnectionStream() {
        connectionTask?.cancel()
        connectionTask = nil
    }

    func startMemoryStream() {
        memoryTask?.cancel()
        guard let client else { return }
        memoryTask = Task { [weak self] in
            do {
                for try await snapshot in client.memoryEvents() {
                    guard let self else { return }
                    markBackendConnected()
                    if let inuse = snapshot.inuse {
                        updateMemory(inuse)
                    }
                }
            } catch where error.isCancellation || Task.isCancelled {
                return
            } catch {
                await self?.pollOverviewStats(client: client)
            }
        }
    }

    func stopMemoryStream() {
        memoryTask?.cancel()
        memoryTask = nil
    }

    func startTrafficStream() {
        trafficTask?.cancel()
        guard let client else { return }
        trafficTask = Task { [weak self] in
            do {
                for try await snapshot in client.trafficEvents() {
                    guard let self else { return }
                    markBackendConnected()
                    updateTraffic(upload: snapshot.up, download: snapshot.down)
                }
            } catch where error.isCancellation || Task.isCancelled {
                return
            } catch {
                await self?.pollOverviewStats(client: client)
            }
        }
    }

    func stopTrafficStream() {
        trafficTask?.cancel()
        trafficTask = nil
    }

    func startLogs() {
        logTask?.cancel()
        logStore.entries.removeAll()
        guard let client else { return }
        let level = logStore.level
        logTask = Task { [weak self] in
            do {
                for try await entry in client.logs(level: level) {
                    guard let self else { return }
                    markBackendConnected()
                    logStore.entries.append(entry)
                    if logStore.entries.count > 400 {
                        logStore.entries.removeFirst(logStore.entries.count - 400)
                    }
                }
            } catch where error.isCancellation || Task.isCancelled {
                return
            } catch {
                self?.beginBackendErrorDebounce(error.localizedDescription)
            }
        }
    }

    func stopLogs() {
        logTask?.cancel()
        logTask = nil
    }

    private func pollConnections(client: any ProxyBackendClient) async {
        while !Task.isCancelled {
            do {
                updateConnections(try await client.connections())
                markBackendConnected()
                try await Task.sleep(for: .seconds(1))
            } catch where error.isCancellation || Task.isCancelled {
                return
            } catch {
                beginBackendErrorDebounce(error.localizedDescription)
                if error.isConnectionFailure {
                    suspendBackgroundRefresh()
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func pollOverviewStats(client: any ProxyBackendClient) async {
        while !Task.isCancelled {
            do {
                applyOverviewStats(try await client.overview())
                markBackendConnected()
                try await Task.sleep(for: .seconds(1))
            } catch where error.isCancellation || Task.isCancelled {
                return
            } catch {
                beginBackendErrorDebounce(error.localizedDescription)
                if error.isConnectionFailure {
                    suspendBackgroundRefresh()
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
