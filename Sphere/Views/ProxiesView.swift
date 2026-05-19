import SwiftUI

struct ProxiesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var proxyColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: horizontalSizeClass == .regular ? 180 : 150, maximum: 280),
                spacing: 8
            ),
        ]
    }
    
    var body: some View {
        NavigationStack {
            List {
                if app.proxyCollection.groups.isEmpty {
                    EmptyStateView(title: "No Proxy Groups", message: "Refresh after backend connects.", systemImage: "point.3.connected.trianglepath.dotted")
                        .listRowBackground(Color.clear)
                } else {
                    if app.selectedProfile?.kind.showsProxyProviders == true {
                        Section("Providers") {
                            if app.proxyProviders.isEmpty {
                                Text("No providers")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(app.proxyProviders) { provider in
                                    ProxyProviderRow(provider: provider) {
                                        Task { await app.refreshProxyProvider(provider.name) }
                                    }
                                }
                            }
                        }
                    }
                    
                    Section {
                        ForEach(app.proxyCollection.groups) { group in
                            ProxyGroupSection(group: group, proxyColumns: proxyColumns)
                        }
                    } header: {
                        HStack(alignment: .center) {
                            Text("Groups")
                            Spacer()
                            HStack(spacing: 8) {
                                ProxyGroupExpansionButton(
                                    title: expansionActionTitle,
                                    symbol: expansionActionSymbol
                                ) {
                                    withAnimation(.smooth(duration: 0.28)) {
                                        app.setAllProxyGroupsExpanded(!allProxyGroupsExpanded, groups: app.proxyCollection.groups)
                                    }
                                }
                                ProxyGroupSpeedTestButton(isTesting: app.isTestingProxyGroupDelays) {
                                    Task { await app.testProxyGroupDelays() }
                                }
                            }
                            .frame(height: 18, alignment: .center)
                        }
                    }
                }
            }
            .backendPageToolbar(tab: .proxies)
            .refreshable {
                await app.refreshProxies(source: .pullToRefresh)
            }
        }
    }
    
    private var allProxyGroupsExpanded: Bool {
        app.areAllProxyGroupsExpanded(app.proxyCollection.groups)
    }
    
    private var expansionActionTitle: String {
        allProxyGroupsExpanded ? "Collapse All" : "Expand All"
    }
    
    private var expansionActionSymbol: String {
        allProxyGroupsExpanded ? "chevron.up" : "chevron.down"
    }
}

struct ProxyGroupExpansionButton: View {
    var title: String
    var symbol: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .frame(width: 64, alignment: .trailing)
                Image(systemName: symbol)
                    .frame(width: 12, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .frame(width: 82, alignment: .trailing)
            .frame(minWidth: 44, minHeight: 44, alignment: .center)
            .font(.caption2)
            .contentShape(.rect)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(title)
    }
}

struct ProxyGroupSpeedTestButton: View {
    var isTesting: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "speedometer")
                    .opacity(isTesting ? 0 : 1)
                    .accessibilityHidden(true)
                if isTesting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.secondary)
                        .transition(.spinnerBadgeAppearance)
                }
            }
            .frame(width: 44, height: 44)
            .font(.caption2)
            .contentShape(.rect)
            .animation(.spinnerBadgeAppearance, value: isTesting)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(isTesting)
        .accessibilityLabel(isTesting ? "Testing node speed" : "Test node speed")
    }
}

struct ProxyGroupSection: View {
    @Environment(AppModel.self) private var app
    @State private var isExpanded = false
    var group: ProxyItem
    var proxyColumns: [GridItem]
    
    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                if isExpanded {
                    LazyVGrid(columns: proxyColumns, spacing: 8) {
                        ForEach(group.all, id: \.self) { proxyName in
                            ProxyChoiceButton(
                                name: proxyName,
                                proxy: app.proxyItem(named: proxyName),
                                isSelected: proxyName == group.now
                            ) {
                                Task { await app.selectProxy(group: group.name, proxy: proxyName) }
                            }
                        }
                    }
                    .padding(.leading, -20)
                    .padding(-5)
                }
            } label: {
                HStack(spacing: 8) {
                    ProxyIconView(icon: group.icon, size: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: group.displayName)
                            .font(.headline)
                        Text("\(group.type) · \(group.all.count) nodes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                isExpanded = app.isProxyGroupExpanded(group.name)
            }
            .onChange(of: group.name) {
                isExpanded = app.isProxyGroupExpanded(group.name)
            }
            .onChange(of: app.proxyGroupExpansionRevision) {
                withAnimation(.smooth(duration: 0.28)) {
                    isExpanded = app.isProxyGroupExpanded(group.name)
                }
            }
            .onChange(of: isExpanded) {
                app.setProxyGroupExpanded(isExpanded, groupName: group.name)
            }
        }
    }
}

struct ProxyProviderRow: View {
    var provider: ProxyProvider
    var refresh: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: provider.name.backendNameForDisplay)
                    Text(provider.vehicleType ?? provider.type ?? "Provider")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remains data: \(ByteFormat.bytes(provider.remainingBytes)) / \(ByteFormat.bytes(provider.totalBytes))")
                    Text("Expire: \(DateFormat.expire(provider.expireAt))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Refresh \(provider.name)")
        }
    }
}

struct ProxyChoiceButton: View {
    var name: String
    var proxy: ProxyItem?
    var isSelected: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    ProxyIconView(icon: proxy?.icon, size: 16)
                    Text(verbatim: proxy?.displayName ?? name.backendNameForDisplay)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.small)
                        .opacity(isSelected ? 1 : 0)
                        .frame(width: 14)
                        .accessibilityHidden(!isSelected)
                }
                
                if let proxy {
                    HStack(spacing: 6) {
                        ProxyMetaLine(proxy: proxy)
                        Spacer(minLength: 0)
                        ProxyDelayBadge(delay: proxy.delay)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)
            )
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(proxy?.displayName ?? name.backendNameForDisplay)\(isSelected ? ", selected" : "")")
    }
}

struct ProxyDelayBadge: View {
    var delay: Int?
    
    var body: some View {
        Group {
            if let delay {
                Text(label(for: delay))
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .foregroundStyle(delay > 0 ? Color.secondary : Color.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .accessibilityLabel(delay > 0 ? "\(delay) milliseconds" : "Latency timeout")
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 50, height: 18, alignment: .trailing)
    }
    
    private func label(for delay: Int) -> String {
        delay > 0 ? "\(delay) ms" : "Timeout"
    }
}

struct ProxyMetaLine: View {
    var proxy: ProxyItem
    
    var body: some View {
        Text(verbatim: proxy.metaBadges.map(\.backendNameForDisplay).joined(separator: " · "))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
}
