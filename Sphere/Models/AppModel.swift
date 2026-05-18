import Foundation
import SwiftUI
import Combine

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

private struct RefreshOutcome {
    var connectionFailed = false
    var backendConnected = false
    var errorMessage: String?

    init() {}

    init(error: Error) {
        guard !error.isCancellation else { return }
        connectionFailed = error.isConnectionFailure
        errorMessage = error.localizedDescription
    }

    mutating func merge(_ other: RefreshOutcome) {
        connectionFailed = connectionFailed || other.connectionFailed
        backendConnected = backendConnected || other.backendConnected
        errorMessage = other.errorMessage ?? errorMessage
    }

    mutating func markBackendConnected() {
        backendConnected = true
    }
}

private extension Error {
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
    @Published private(set) var isAutoRefreshSuspended = false
    @Published private(set) var isBackendErrorDebouncing = false
    @Published private(set) var isManualRefreshActive = false
    @Published private(set) var toolbarRefreshingTabs: Set<AppTab> = []
    @Published private(set) var isTestingProxyGroupDelays = false
    @Published private(set) var proxyGroupExpansionRevision = 0

    let liveStore = LiveBackendStore()
    let logStore = LogStore()

    private let defaults: UserDefaults
    private let makeClient: @MainActor (APIProfile) -> any ProxyBackendClient
    private let progressActivityReporter: any ProgressActivityReporting
    private let backendErrorDebounceDuration: Duration
    private var connectionTask: Task<Void, Never>?
    private var memoryTask: Task<Void, Never>?
    private var trafficTask: Task<Void, Never>?
    private var logTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private var backendErrorTask: Task<Void, Never>?
    private var cacheSaveTask: Task<Void, Never>?
    private var backendSuccessGeneration = 0
    private var manualRefreshDepth = 0
    private var pendingBackendErrorMessage: String?
    private var lastCacheSave = Date.distantPast
    private var proxyLookup: [String: ProxyItem] = [:]
    private var proxyGroupIcons: [String: String] = [:]
    private var loadedProxyGroupIconsKey: String?
    private let cacheSaveInterval: TimeInterval = 5

    private enum Keys {
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
        if source == .automatic && isAutoRefreshSuspended {
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
                    self.markBackendConnected()
                    self.updateConnections(snapshot)
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
                    self.markBackendConnected()
                    if let inuse = snapshot.inuse {
                        self.updateMemory(inuse)
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
                    self.markBackendConnected()
                    self.updateTraffic(upload: snapshot.up, download: snapshot.down)
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
                    self.markBackendConnected()
                    self.logStore.entries.append(entry)
                    if self.logStore.entries.count > 400 {
                        self.logStore.entries.removeFirst(self.logStore.entries.count - 400)
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

    private func updateConnections(_ snapshot: ConnectionsSnapshot) {
        var didChange = false
        if connections != snapshot {
            connections = snapshot
            didChange = true
        }
        let count = snapshot.connections.count
        if overview.activeConnections != count {
            overview.activeConnections = count
            didChange = true
        }
        if didChange {
            scheduleCacheSave()
        }
    }

    private func updateMemory(_ memoryBytes: Int) {
        guard overview.memoryBytes != memoryBytes else { return }
        overview.memoryBytes = memoryBytes
        scheduleCacheSave()
    }

    private func updateTraffic(upload: Int, download: Int) {
        guard overview.uploadBytesPerSecond != upload || overview.downloadBytesPerSecond != download else { return }
        overview.uploadBytesPerSecond = upload
        overview.downloadBytesPerSecond = download
        scheduleCacheSave()
    }

    private func result<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func apply<T>(_ result: Result<T, Error>, onSuccess: (T) -> Void) -> RefreshOutcome {
        switch result {
        case .success(let value):
            onSuccess(value)
            var outcome = RefreshOutcome()
            outcome.markBackendConnected()
            return outcome
        case .failure(let error):
            return RefreshOutcome(error: error)
        }
    }

    private func captureErrors(_ operation: () async throws -> Void) async -> RefreshOutcome {
        do {
            try await operation()
            markBackendConnected()
            var outcome = RefreshOutcome()
            outcome.markBackendConnected()
            return outcome
        } catch {
            guard !error.isCancellation else { return RefreshOutcome() }
            let outcome = RefreshOutcome(error: error)
            beginBackendErrorDebounce(error.localizedDescription)
            return outcome
        }
    }

    private func delayProxyGroups(
        client: any ProxyBackendClient,
        groupNames: [String],
        progress: ((Int, Int) async -> Void)? = nil
    ) async throws -> [String: Int] {
        var mergedDelays: [String: Int] = [:]
        var firstError: Error?
        var successCount = 0
        var startIndex = groupNames.startIndex
        var completedCount = 0

        while startIndex < groupNames.endIndex {
            let endIndex = groupNames.index(startIndex, offsetBy: ProxyLatencyTestDefaults.maxConcurrentGroups, limitedBy: groupNames.endIndex) ?? groupNames.endIndex
            let batch = Array(groupNames[startIndex..<endIndex])
            let results = await withTaskGroup(of: Result<[String: Int], Error>.self) { taskGroup in
                for groupName in batch {
                    taskGroup.addTask {
                        do {
                            return .success(try await client.delayProxyGroup(
                                groupName,
                                url: ProxyLatencyTestDefaults.url,
                                timeout: ProxyLatencyTestDefaults.timeout
                            ))
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                var values: [Result<[String: Int], Error>] = []
                for await result in taskGroup {
                    values.append(result)
                }
                return values
            }

            for result in results {
                switch result {
                case .success(let delays):
                    successCount += 1
                    mergedDelays.merge(delays) { _, next in next }
                case .failure(let error):
                    firstError = firstError ?? error
                }
            }
            completedCount += batch.count
            await progress?(completedCount, groupNames.count)
            startIndex = endIndex
        }

        if successCount == 0, let firstError {
            throw firstError
        }
        return mergedDelays
    }

    private func prepareRefresh(source: RefreshSource) {
        if source.isUserInitiated {
            manualRefreshDepth += 1
            isManualRefreshActive = true
            isAutoRefreshSuspended = false
        }
    }

    private func finishRefresh(_ outcome: RefreshOutcome, source: RefreshSource) async {
        defer { finishManualRefresh(source: source) }
        if outcome.backendConnected {
            markBackendConnected()
        } else if let message = outcome.errorMessage {
            beginBackendErrorDebounce(message)
        }
        if outcome.connectionFailed {
            suspendBackgroundRefresh()
        } else if source.isUserInitiated {
            isAutoRefreshSuspended = false
            startLiveStreams()
            startAutoRefresh()
        }
        if source.waitsForBackendErrorDebounce {
            await waitForBackendErrorDebounceIfNeeded()
        }
    }

    private func suspendBackgroundRefresh() {
        isAutoRefreshSuspended = true
        stopAutoRefresh()
        stopLiveStreams()
    }

    private func finishManualRefresh(source: RefreshSource) {
        guard source.isUserInitiated else { return }
        manualRefreshDepth = max(0, manualRefreshDepth - 1)
        if manualRefreshDepth == 0 {
            isManualRefreshActive = false
        }
    }

    private func waitForBackendErrorDebounceIfNeeded() async {
        guard isBackendErrorDebouncing, let backendErrorTask else { return }
        await backendErrorTask.value
    }

    private func markBackendConnected() {
        backendSuccessGeneration &+= 1
        guard isBackendErrorDebouncing || errorMessage != nil || backendErrorTask != nil || pendingBackendErrorMessage != nil else {
            return
        }
        backendErrorTask?.cancel()
        backendErrorTask = nil
        pendingBackendErrorMessage = nil
        isBackendErrorDebouncing = false
        errorMessage = nil
    }

    private func beginBackendErrorDebounce(_ message: String) {
        pendingBackendErrorMessage = message
        guard !isBackendErrorDebouncing else { return }
        backendErrorTask?.cancel()
        errorMessage = nil
        isBackendErrorDebouncing = true
        let generation = backendSuccessGeneration
        let duration = backendErrorDebounceDuration
        backendErrorTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            self?.confirmBackendError(startedAtGeneration: generation)
        }
    }

    private func confirmBackendError(startedAtGeneration generation: Int) {
        backendErrorTask = nil
        guard backendSuccessGeneration == generation else {
            pendingBackendErrorMessage = nil
            isBackendErrorDebouncing = false
            errorMessage = nil
            return
        }
        errorMessage = pendingBackendErrorMessage
        pendingBackendErrorMessage = nil
        isBackendErrorDebouncing = false
    }

    private func resetLoadedData() {
        stopLiveStreams()
        stopAutoRefresh()
        backendErrorTask?.cancel()
        cacheSaveTask?.cancel()
        backendErrorTask = nil
        cacheSaveTask = nil
        pendingBackendErrorMessage = nil
        isBackendErrorDebouncing = false
        isManualRefreshActive = false
        toolbarRefreshingTabs.removeAll()
        manualRefreshDepth = 0
        errorMessage = nil
        backendSuccessGeneration &+= 1
        liveStore.reset()
        proxyCollection = ProxyCollection()
        rebuildProxyLookup()
        proxyGroupIcons = [:]
        loadedProxyGroupIconsKey = nil
        proxyProviders = []
        rules = []
        ruleProviders = []
        logStore.reset()
        configs = [:]
        clashMode = .rule
    }

    private func proxyGroupExpandedKey(_ groupName: String) -> String {
        "\(Keys.proxyGroupExpandedPrefix).\(selectedProfileID?.uuidString ?? "none").\(groupName)"
    }

    private func cacheKey(profileID: UUID?) -> String {
        "\(Keys.cachedDataPrefix).\(profileID?.uuidString ?? "none")"
    }

    private func cacheKey() -> String {
        cacheKey(profileID: selectedProfileID)
    }

    private func proxyGroupIconsKey() -> String {
        "\(Keys.proxyGroupIconsPrefix).\(selectedProfileID?.uuidString ?? "none")"
    }

    private func loadCachedData() {
        guard let data = defaults.data(forKey: cacheKey()),
              let snapshot = try? JSONDecoder().decode(BackendDataCache.self, from: data)
        else { return }
        overview = snapshot.overview
        proxyCollection = restoringCachedProxyGroupIcons(in: snapshot.proxyCollection)
        rebuildProxyLookup()
        proxyProviders = snapshot.proxyProviders
        rules = snapshot.rules
        ruleProviders = snapshot.ruleProviders
        connections = snapshot.connections
        configs = snapshot.configs
        clashMode = snapshot.clashMode
    }

    private func saveCachedDataIfUseful() {
        guard hasCacheableData else { return }
        let snapshot = BackendDataCache(
            overview: overview,
            proxyCollection: proxyCollection,
            proxyProviders: proxyProviders,
            rules: rules,
            ruleProviders: ruleProviders,
            connections: connections,
            configs: configs,
            clashMode: clashMode
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: cacheKey())
            lastCacheSave = Date()
        }
    }

    private func scheduleCacheSave() {
        guard hasCacheableData else { return }
        let delay = cacheSaveInterval - Date().timeIntervalSince(lastCacheSave)
        guard delay > 0 else {
            saveCachedDataIfUseful()
            return
        }
        cacheSaveTask?.cancel()
        cacheSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            self?.saveCachedDataIfUseful()
        }
    }

    private func flushPendingCacheSave() {
        guard cacheSaveTask != nil else { return }
        cacheSaveTask?.cancel()
        cacheSaveTask = nil
        saveCachedDataIfUseful()
    }

    @discardableResult
    private func setProxyCollection(_ collection: ProxyCollection) -> Bool {
        let nextCollection = restoringCachedProxyGroupIcons(in: collection)
        guard proxyCollection != nextCollection else {
            return mergeProxyGroupIcons(from: nextCollection.groups)
        }
        proxyCollection = nextCollection
        rebuildProxyLookup()
        _ = mergeProxyGroupIcons(from: nextCollection.groups)
        return true
    }

    @discardableResult
    private func setProxyProviders(_ providers: [ProxyProvider]) -> Bool {
        guard proxyProviders != providers else { return false }
        proxyProviders = providers
        return true
    }

    func proxyItem(named name: String) -> ProxyItem? {
        proxyLookup[name] ?? proxyCollection.item(named: name)
    }

    private func rebuildProxyLookup() {
        let pairs = (proxyCollection.proxies + proxyCollection.groups).map { ($0.name, $0) }
        proxyLookup = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    private func ensureProxyGroupIconsLoaded() {
        let key = proxyGroupIconsKey()
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

    private func restoringCachedProxyGroupIcons(in collection: ProxyCollection) -> ProxyCollection {
        ensureProxyGroupIconsLoaded()
        guard !proxyGroupIcons.isEmpty else { return collection }
        var next = collection
        var restoredIcon = false
        next.groups = collection.groups.map { group in
            guard (group.icon?.isEmpty ?? true), let icon = proxyGroupIcons[group.name] else { return group }
            restoredIcon = true
            var copy = group
            copy.icon = icon
            return copy
        }
        return restoredIcon ? next : collection
    }

    private func mergeProxyGroupIcons(from groups: [ProxyItem]) -> Bool {
        ensureProxyGroupIconsLoaded()
        var changed = false
        for group in groups {
            guard let icon = group.icon, !icon.isEmpty else { continue }
            if proxyGroupIcons[group.name] != icon {
                proxyGroupIcons[group.name] = icon
                changed = true
            }
        }
        guard changed else { return false }
        saveProxyGroupIcons()
        return true
    }

    private func saveProxyGroupIcons() {
        guard let data = try? JSONEncoder().encode(proxyGroupIcons) else { return }
        defaults.set(data, forKey: proxyGroupIconsKey())
    }

    private func applyOverviewStats(_ nextOverview: BackendOverview) {
        var didChange = false
        if let uptime = nextOverview.uptime, overview.uptime != uptime {
            overview.uptime = uptime
            didChange = true
        }
        if let memoryBytes = nextOverview.memoryBytes, overview.memoryBytes != memoryBytes {
            overview.memoryBytes = memoryBytes
            didChange = true
        }
        if let uploadBytesPerSecond = nextOverview.uploadBytesPerSecond, overview.uploadBytesPerSecond != uploadBytesPerSecond {
            overview.uploadBytesPerSecond = uploadBytesPerSecond
            didChange = true
        }
        if let downloadBytesPerSecond = nextOverview.downloadBytesPerSecond, overview.downloadBytesPerSecond != downloadBytesPerSecond {
            overview.downloadBytesPerSecond = downloadBytesPerSecond
            didChange = true
        }
        if let activeConnections = nextOverview.activeConnections, overview.activeConnections != activeConnections {
            overview.activeConnections = activeConnections
            didChange = true
        }
        if didChange {
            scheduleCacheSave()
        }
    }

    private func applyVersion(_ version: String) {
        guard version != overview.version else { return }
        overview.version = version
    }

    private func applyConfigs(_ values: [String: JSONValue]) {
        configs = values
        if case .string(let mode)? = values["mode"],
           let decodedMode = ClashMode(mihomoValue: mode) {
            clashMode = decodedMode
        }
    }

    private var hasCacheableData: Bool {
        overview != .empty ||
            !proxyCollection.proxies.isEmpty ||
            !proxyCollection.groups.isEmpty ||
            !proxyProviders.isEmpty ||
            !rules.isEmpty ||
            !ruleProviders.isEmpty ||
            !connections.connections.isEmpty ||
            !configs.isEmpty
    }
}

private struct BackendDataCache: Codable {
    var overview: BackendOverview
    var proxyCollection: ProxyCollection
    var proxyProviders: [ProxyProvider]
    var rules: [RuleItem]
    var ruleProviders: [RuleProvider]
    var connections: ConnectionsSnapshot
    var configs: [String: JSONValue]
    var clashMode: ClashMode
}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case proxies
    case rule
    case connections
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .proxies:
            return "Proxies"
        case .rule:
            return "Rule"
        case .connections:
            return "Connections"
        case .more:
            return "More"
        }
    }

    var symbol: String {
        switch self {
        case .proxies:
            return "point.3.connected.trianglepath.dotted"
        case .rule:
            return "list.bullet.rectangle"
        case .connections:
            return "bolt.horizontal.circle"
        case .more:
            return "ellipsis.circle"
        }
    }
}
