import SwiftUI
import UIKit

struct RootView: View {
    @StateObject private var app = AppModel()

    var body: some View {
        Group {
            if app.hasProfiles {
                AppTabView()
                    .environmentObject(app)
                    .environmentObject(app.liveStore)
                    .environmentObject(app.logStore)
            } else {
                ProfileWizardView()
                    .environmentObject(app)
            }
        }
    }
}

struct AppTabView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
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
    @EnvironmentObject private var app: AppModel

    func body(content: Content) -> some View {
        content
            .task(id: VisibleRefreshKey(profileID: app.selectedProfileID, tab: app.selectedTab)) {
                app.stopAutoRefresh()
                app.startLiveStreams()
                await app.refreshSelectedTab(source: .automatic)
                if !Task.isCancelled {
                    app.startAutoRefresh()
                }
            }
            .onDisappear {
                app.stopLiveStreams()
                app.stopAutoRefresh()
            }
    }
}

private struct VisibleRefreshKey: Equatable {
    var profileID: UUID?
    var tab: AppTab
}
