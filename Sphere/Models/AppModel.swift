import Foundation
import Observation
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

private enum RefreshAllValue: Sendable {
    case version(Result<String, Error>)
    case overview(Result<BackendOverview, Error>)
    case proxies(Result<ProxyCollection, Error>)
    case proxyProviders(Result<[ProxyProvider], Error>)
    case rules(Result<[RuleItem], Error>)
    case ruleProviders(Result<[RuleProvider], Error>)
    case configs(Result<[String: JSONValue], Error>)
    case mode(Result<ClashMode, Error>)
}

private enum RefreshProxiesValue: Sendable {
    case proxies(Result<ProxyCollection, Error>)
    case proxyProviders(Result<[ProxyProvider], Error>)
}

private enum RefreshRulesValue: Sendable {
    case rules(Result<[RuleItem], Error>)
    case ruleProviders(Result<[RuleProvider], Error>)
    case configs(Result<[String: JSONValue], Error>)
}

nonisolated private func backendResult<T: Sendable>(
    _ operation: @Sendable () async throws -> T
) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
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

@Observable
@MainActor
final class AppModel {
    let profileStore: ProfileStore
    let proxyStore: ProxyStore
    let configStore: ConfigStore
    let liveState: LiveState

    var selectedTab: AppTab = .proxies
    var isLoading = false
    var errorMessage: String?
    var isUpdatingCore = false
    var isAutoRefreshSuspended = false
    var isBackendErrorDebouncing = false
    var isManualRefreshActive = false
    var toolbarRefreshingTabs: Set<AppTab> = []
    var backendErrorDebounceRevision = 0
    var cacheSaveRevision = 0

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private let makeClient: @MainActor (APIProfile) -> any ProxyBackendClient
    @ObservationIgnored private let progressActivityReporter: any ProgressActivityReporting
    @ObservationIgnored let backendErrorDebounceDuration: Duration
    @ObservationIgnored var backendSuccessGeneration = 0
    @ObservationIgnored var backendErrorStartedAtGeneration = 0
    @ObservationIgnored var manualRefreshDepth = 0
    @ObservationIgnored var pendingBackendErrorMessage: String?
    @ObservationIgnored var pendingCacheSave = false
    @ObservationIgnored var lastCacheSave = Date.distantPast
    @ObservationIgnored let cacheSaveInterval: TimeInterval = 5

    init(
        defaults: UserDefaults = .standard,
        backendErrorDebounceDuration: Duration = .seconds(5),
        progressActivityReporter: (any ProgressActivityReporting)? = nil,
        clientFactory: @escaping @MainActor (APIProfile) -> any ProxyBackendClient = BackendClientFactory.make(profile:)
    ) {
        self.defaults = defaults
        self.profileStore = ProfileStore(defaults: defaults)
        self.proxyStore = ProxyStore(defaults: defaults)
        self.configStore = ConfigStore()
        self.liveState = LiveState()
        self.backendErrorDebounceDuration = backendErrorDebounceDuration
        self.progressActivityReporter = progressActivityReporter ?? ProgressActivityReporterFactory.makeDefault()
        self.makeClient = clientFactory
        loadCachedData()
    }

    var profiles: [APIProfile] {
        get { profileStore.profiles }
        set { profileStore.profiles = newValue }
    }

    var selectedProfileID: UUID? {
        get { profileStore.selectedProfileID }
        set { profileStore.selectedProfileID = newValue }
    }

    var proxyCollection: ProxyCollection {
        get { proxyStore.proxyCollection }
        set {
            proxyStore.proxyCollection = newValue
            proxyStore.rebuildProxyLookup()
        }
    }

    var proxyProviders: [ProxyProvider] {
        get { proxyStore.proxyProviders }
        set { proxyStore.proxyProviders = newValue }
    }

    var rules: [RuleItem] {
        get { configStore.rules }
        set { configStore.rules = newValue }
    }

    var ruleProviders: [RuleProvider] {
        get { configStore.ruleProviders }
        set { configStore.ruleProviders = newValue }
    }

    var configs: [String: JSONValue] {
        get { configStore.configs }
        set { configStore.configs = newValue }
    }

    var clashMode: ClashMode {
        get { configStore.clashMode }
        set { configStore.clashMode = newValue }
    }

    var isTestingProxyGroupDelays: Bool {
        proxyStore.isTestingProxyGroupDelays
    }

    var proxyGroupExpansionRevision: Int {
        proxyStore.proxyGroupExpansionRevision
    }

    var overview: BackendOverview {
        get { liveState.overview }
        set { liveState.overview = newValue }
    }

    var connections: ConnectionsSnapshot {
        get { liveState.connections }
        set { liveState.connections = newValue }
    }

    var logs: [LogEntry] {
        get { liveState.logs }
        set { liveState.logs = newValue }
    }

    var logLevel: LogLevel {
        get { liveState.logLevel }
        set { liveState.logLevel = newValue }
    }

    var selectedProfile: APIProfile? {
        profileStore.selectedProfile
    }

    var hasProfiles: Bool {
        profileStore.hasProfiles
    }

    var client: (any ProxyBackendClient)? {
        selectedProfile.map(makeClient)
    }

    var canUpdateCore: Bool {
        selectedProfile?.kind == .mihomo && !overview.version.localizedStandardContains("sing-box")
    }

    var visibleBackendErrorMessage: String? {
        isManualRefreshActive ? nil : errorMessage
    }

    var showsBackendErrorSpinner: Bool {
        isBackendErrorDebouncing && !isManualRefreshActive
    }
}

@MainActor
extension AppModel {
    func loadProfiles() {
        profileStore.loadProfiles()
    }

    func addProfile(_ profile: APIProfile) {
        profileStore.addProfile(profile)
        selectedTab = .proxies
    }

    func updateProfile(_ profile: APIProfile) {
        let shouldReset = profileStore.updateProfile(profile)
        if shouldReset {
            defaults.removeObject(forKey: cacheKey(profileID: profile.id))
            resetLoadedData()
        }
    }

    func deleteProfiles(at offsets: IndexSet) {
        flushPendingCacheSave()
        if profileStore.deleteProfiles(at: offsets) {
            resetLoadedData()
            loadCachedData()
        }
    }

    func deleteProfile(_ profile: APIProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        deleteProfiles(at: IndexSet(integer: index))
    }

    func moveProfiles(from offsets: IndexSet, to destination: Int) {
        profileStore.moveProfiles(from: offsets, to: destination)
    }

    func selectProfile(_ id: UUID?) {
        flushPendingCacheSave()
        guard profileStore.selectProfile(id) else { return }
        resetLoadedData()
        loadCachedData()
    }

    func saveProfiles() {
        profileStore.saveProfiles()
    }

    func testProfile(_ profile: APIProfile) async throws -> BackendOverview {
        try await makeClient(profile).testConnection()
    }

    func refreshAll(source: RefreshSource = .manual) async {
        guard let client else { return }
        prepareRefresh(source: source)
        isLoading = true
        defer { isLoading = false }

        var outcome = RefreshOutcome()
        await withTaskGroup(of: RefreshAllValue.self) { taskGroup in
            taskGroup.addTask { .version(await backendResult { try await client.version() }) }
            taskGroup.addTask { .overview(await backendResult { try await client.overview() }) }
            taskGroup.addTask { .proxies(await backendResult { try await client.proxies() }) }
            taskGroup.addTask { .proxyProviders(await backendResult { try await client.proxyProviders() }) }
            taskGroup.addTask { .rules(await backendResult { try await client.rules() }) }
            taskGroup.addTask { .ruleProviders(await backendResult { try await client.ruleProviders() }) }
            taskGroup.addTask { .configs(await backendResult { try await client.configs() }) }
            taskGroup.addTask { .mode(await backendResult { try await client.clashMode() }) }

            for await value in taskGroup {
                switch value {
                case .version(let result):
                    outcome.merge(apply(result) { applyVersion($0) })
                case .overview(let result):
                    outcome.merge(apply(result) { applyOverviewStats($0) })
                case .proxies(let result):
                    outcome.merge(apply(result) { setProxyCollection($0) })
                case .proxyProviders(let result):
                    outcome.merge(apply(result) { proxyProviders = $0 })
                case .rules(let result):
                    outcome.merge(apply(result) { rules = $0 })
                case .ruleProviders(let result):
                    outcome.merge(apply(result) { ruleProviders = $0 })
                case .configs(let result):
                    outcome.merge(apply(result) { applyConfigs($0) })
                case .mode(let result):
                    outcome.merge(apply(result) { clashMode = $0 })
                }
            }
        }
        saveCachedDataIfUseful()
        await finishRefresh(outcome, source: source)
    }

    func runAutoRefreshLoop() async {
        guard !isAutoRefreshSuspended else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, !isAutoRefreshSuspended else { return }
            await refreshSelectedTab(source: .automatic)
        }
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

        var outcome = RefreshOutcome()
        var didChange = false

        await withTaskGroup(of: RefreshProxiesValue.self) { taskGroup in
            taskGroup.addTask { .proxies(await backendResult { try await client.proxies() }) }
            taskGroup.addTask { .proxyProviders(await backendResult { try await client.proxyProviders() }) }

            for await value in taskGroup {
                switch value {
                case .proxies(let result):
                    switch result {
                    case .success(let collection):
                        didChange = setProxyCollection(collection) || didChange
                        outcome.markBackendConnected()
                    case .failure(let error):
                        outcome.merge(RefreshOutcome(error: error))
                    }
                case .proxyProviders(let result):
                    switch result {
                    case .success(let providers):
                        didChange = setProxyProviders(providers) || didChange
                        outcome.markBackendConnected()
                    case .failure(let error):
                        outcome.merge(RefreshOutcome(error: error))
                    }
                }
            }
        }

        if didChange {
            saveCachedDataIfUseful()
        }
        await finishRefresh(outcome, source: source)
    }

    func refreshRules(source: RefreshSource = .manual) async {
        guard let client else { return }
        prepareRefresh(source: source)

        var outcome = RefreshOutcome()
        await withTaskGroup(of: RefreshRulesValue.self) { taskGroup in
            taskGroup.addTask { .rules(await backendResult { try await client.rules() }) }
            taskGroup.addTask { .ruleProviders(await backendResult { try await client.ruleProviders() }) }
            taskGroup.addTask { .configs(await backendResult { try await client.configs() }) }

            for await value in taskGroup {
                switch value {
                case .rules(let result):
                    outcome.merge(apply(result) { rules = $0 })
                case .ruleProviders(let result):
                    outcome.merge(apply(result) { ruleProviders = $0 })
                case .configs(let result):
                    outcome.merge(apply(result) { applyConfigs($0) })
                }
            }
        }
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

        proxyStore.isTestingProxyGroupDelays = true
        defer { proxyStore.isTestingProxyGroupDelays = false }

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

    func isProxyGroupExpanded(_ groupName: String) -> Bool {
        proxyStore.isProxyGroupExpanded(groupName, profileID: selectedProfileID)
    }

    func areAllProxyGroupsExpanded(_ groups: [ProxyItem]) -> Bool {
        proxyStore.areAllProxyGroupsExpanded(groups, profileID: selectedProfileID)
    }

    func setProxyGroupExpanded(_ isExpanded: Bool, groupName: String) {
        proxyStore.setProxyGroupExpanded(isExpanded, groupName: groupName, profileID: selectedProfileID)
    }

    func setAllProxyGroupsExpanded(_ isExpanded: Bool, groups: [ProxyItem]) {
        proxyStore.setAllProxyGroupsExpanded(isExpanded, groups: groups, profileID: selectedProfileID)
    }

    func streamConnections() async {
        guard let client else { return }
        defer { flushPendingCacheSave() }
        do {
            for try await snapshot in client.connectionEvents(interval: 1000) {
                markBackendConnected()
                updateConnections(snapshot)
            }
        } catch where error.isCancellation || Task.isCancelled {
            return
        } catch {
            await pollConnections(client: client)
        }
    }

    func streamMemory() async {
        guard let client else { return }
        defer { flushPendingCacheSave() }
        do {
            for try await snapshot in client.memoryEvents() {
                markBackendConnected()
                if let inuse = snapshot.inuse {
                    updateMemory(inuse)
                }
            }
        } catch where error.isCancellation || Task.isCancelled {
            return
        } catch {
            await pollOverviewStats(client: client)
        }
    }

    func streamTraffic() async {
        guard let client else { return }
        defer { flushPendingCacheSave() }
        do {
            for try await snapshot in client.trafficEvents() {
                markBackendConnected()
                updateTraffic(upload: snapshot.up, download: snapshot.down)
            }
        } catch where error.isCancellation || Task.isCancelled {
            return
        } catch {
            await pollOverviewStats(client: client)
        }
    }

    func streamLogs(level: LogLevel) async {
        liveState.logs.removeAll()
        guard let client else { return }
        do {
            for try await entry in client.logs(level: level) {
                markBackendConnected()
                liveState.logs.append(entry)
                if liveState.logs.count > 400 {
                    liveState.logs.removeFirst(liveState.logs.count - 400)
                }
            }
        } catch where error.isCancellation || Task.isCancelled {
            return
        } catch {
            beginBackendErrorDebounce(error.localizedDescription)
        }
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
