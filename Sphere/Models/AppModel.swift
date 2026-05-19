import Foundation
import Observation

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
    @ObservationIgnored let makeClient: @MainActor (APIProfile) -> any ProxyBackendClient
    @ObservationIgnored let progressActivityReporter: any ProgressActivityReporting
    @ObservationIgnored let backendErrorDebounceDuration: Duration
    @ObservationIgnored var backendSuccessGeneration = 0
    @ObservationIgnored var backendErrorStartedAtGeneration = 0
    @ObservationIgnored var manualRefreshDepth = 0
    @ObservationIgnored var pendingBackendErrorMessage: String?
    @ObservationIgnored var pendingCacheSave = false
    @ObservationIgnored var loadedCacheProfileID: UUID?
    @ObservationIgnored var lastCacheSave = Date.distantPast
    @ObservationIgnored let cacheSaveInterval: TimeInterval = 5
    
    init(
        defaults: UserDefaults = .standard,
        backendErrorDebounceDuration: Duration = .seconds(5),
        progressActivityReporter: (any ProgressActivityReporting)? = nil,
        loadsProfilesImmediately: Bool = true,
        clientFactory: @escaping @MainActor (APIProfile) -> any ProxyBackendClient = BackendClientFactory.make(profile:)
    ) {
        self.defaults = defaults
        self.profileStore = ProfileStore(defaults: defaults, loadsProfilesImmediately: loadsProfilesImmediately)
        self.proxyStore = ProxyStore(defaults: defaults)
        self.configStore = ConfigStore()
        self.liveState = LiveState()
        self.backendErrorDebounceDuration = backendErrorDebounceDuration
        self.progressActivityReporter = progressActivityReporter ?? ProgressActivityReporterFactory.makeDefault()
        self.makeClient = clientFactory
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
