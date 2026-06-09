import SwiftUI

struct RootView: View {
    @State private var app = AppModel(loadsProfilesImmediately: false)
    @State private var didLoadStartupData = false
    @State private var pendingURLSchemeURLs: [URL] = []

    var body: some View {
        Group {
            if !didLoadStartupData {
                RootStartupView()
                    .transition(.opacity)
            } else if app.hasProfiles {
                AppTabView()
                    .environment(app)
                    .environment(app.liveState)
                    .transition(.opacity)
            } else {
                ProfileWizardView()
                    .environment(app)
                    .environment(app.liveState)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: didLoadStartupData)
        .task {
            await loadStartupDataIfNeeded()
        }
        .onOpenURL { url in
            pendingURLSchemeURLs.append(url)
            Task {
                await handlePendingURLSchemeURLsIfReady()
            }
        }
        .onChange(of: didLoadStartupData) {
            Task {
                await handlePendingURLSchemeURLsIfReady()
            }
        }
    }

    @MainActor
    private func loadStartupDataIfNeeded() async {
        guard !didLoadStartupData else { return }
        await app.loadProfilesOffMain()
        if app.hasProfiles {
            await app.loadCachedDataIfNeeded()
        }
        didLoadStartupData = true
    }

    @MainActor
    private func handlePendingURLSchemeURLsIfReady() async {
        guard didLoadStartupData else { return }
        let urls = pendingURLSchemeURLs
        pendingURLSchemeURLs.removeAll()
        for url in urls {
            await app.handleURLScheme(url)
        }
    }
}

struct AppTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    AppTabContent(tab: tab)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .modifier(VisibleRefreshLifecycle())
    }
}

private struct AppTabContent: View {
    var tab: AppTab

    var body: some View {
        switch tab {
        case .proxies:
            ProxiesView()
        case .rule:
            RuleView()
        case .connections:
            ConnectionsView()
        case .more:
            MoreView()
        }
    }
}

private struct VisibleRefreshLifecycle: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content
            .task(id: VisibleRefreshKey(profileID: app.selectedProfileID, tab: app.selectedTab)) {
                await app.loadCachedDataIfNeeded()
                await InitialRenderDelay.wait()
                await app.refreshSelectedTab(source: .automatic)
            }
            .task(
                id: AutoRefreshKey(
                    profileID: app.selectedProfileID, tab: app.selectedTab,
                    suspended: app.isAutoRefreshSuspended)
            ) {
                await app.runAutoRefreshLoop()
            }
            .task(
                id: LiveStreamKey(
                    profileID: app.selectedProfileID, tab: app.selectedTab,
                    suspended: app.isAutoRefreshSuspended, stream: .connections)
            ) {
                guard !app.isAutoRefreshSuspended,
                    app.selectedTab == .connections || app.selectedTab == .more
                else { return }
                await app.streamConnections()
            }
            .task(
                id: LiveStreamKey(
                    profileID: app.selectedProfileID, tab: app.selectedTab,
                    suspended: app.isAutoRefreshSuspended, stream: .memory)
            ) {
                guard !app.isAutoRefreshSuspended, app.selectedTab == .more else { return }
                await app.streamMemory()
            }
            .task(
                id: LiveStreamKey(
                    profileID: app.selectedProfileID, tab: app.selectedTab,
                    suspended: app.isAutoRefreshSuspended, stream: .traffic)
            ) {
                guard !app.isAutoRefreshSuspended, app.selectedTab == .more else { return }
                await app.streamTraffic()
            }
            .task(id: app.backendErrorDebounceRevision) {
                await app.runBackendErrorDebounce()
            }
            .task(id: app.cacheSaveRevision) {
                await app.runPendingCacheSave()
            }
            .onDisappear {
                app.flushPendingCacheSave()
            }
    }
}

private struct VisibleRefreshKey: Equatable {
    var profileID: UUID?
    var tab: AppTab
}

private struct AutoRefreshKey: Equatable {
    var profileID: UUID?
    var tab: AppTab
    var suspended: Bool
}

private struct LiveStreamKey: Equatable {
    enum Stream {
        case connections
        case memory
        case traffic
    }

    var profileID: UUID?
    var tab: AppTab
    var suspended: Bool
    var stream: Stream
}

private enum InitialRenderDelay {
    static func wait() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(200))
    }
}
