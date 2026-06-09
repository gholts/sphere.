import SwiftUI

struct ConnectionsView: View {
    @Environment(AppModel.self) private var app
    @Environment(LiveState.self) private var live
    @State private var showSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section("Live") {
                    AdaptiveStatRows(metrics: liveMetrics)
                    SourceIPTagsInlineEditor(sourceIPs: sourceIPs)
                }

                Button {
                    showSheet = true
                } label: {
                    Label("Show Connections", systemImage: "list.bullet")
                }

                Button(role: .destructive) {
                    Task { await app.closeAllConnections() }
                } label: {
                    Label {
                        Text("Close All")
                    } icon: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                    }
                }
            }
            .backendPageToolbar(tab: .connections)
            .refreshable {
                await app.refreshConnections(source: .pullToRefresh)
            }
            .sheet(isPresented: $showSheet) {
                ConnectionsSheetView()
                    .environment(app)
                    .environment(live)
            }
        }
    }

    private var liveMetrics: [StatMetric] {
        var metrics = [
            StatMetric(title: "Active", value: "\(live.connections.connections.count)")
        ]
        if app.selectedProfile?.kind != .surge {
            metrics.append(
                StatMetric(title: "Uploaded", value: ByteFormat.bytes(live.connections.uploadTotal))
            )
            metrics.append(
                StatMetric(
                    title: "Downloaded", value: ByteFormat.bytes(live.connections.downloadTotal)))
        }
        return metrics
    }

    private var sourceIPs: [String] {
        app.currentSourceIPs(from: live.connections.connections)
    }
}

struct ConnectionsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(LiveState.self) private var live
    @State private var filter = ConnectionFilter()
    @State private var autoReorder = true
    @State private var connectionOrder: [String] = []
    @State private var rawJSONConnection: ConnectionInfo?

    var body: some View {
        NavigationStack {
            List {
                Section("Filters") {
                    ConnectionSourceFilterMenu(
                        selection: $filter.sourceIP,
                        options: sourceIPFilterOptions
                    )
                    TextField("Outbound / Rule", text: $filter.outbound)
                        .textInputAutocapitalization(.never)
                    Stepper(value: $filter.minimumDownloadBytes, in: 0...1_000_000_000, step: 1024) {
                        Text("Min download: \(ByteFormat.bytes(filter.minimumDownloadBytes))")
                    }
                    if !filter.isEmpty {
                        Button("Reset Filters", systemImage: "xmark.circle") {
                            filter.reset()
                        }
                    }
                }

                Section {
                    if filteredConnections.isEmpty {
                        EmptyStateView(
                            title: filter.isEmpty ? "No Connections" : "No Matches",
                            message: filter.isEmpty ? "No active connections." : "Change filters.",
                            systemImage: filter.isEmpty ? "network.slash" : "line.3.horizontal.decrease.circle"
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredConnections) { connection in
                            ConnectionRow(
                                connection: connection,
                                sourceIPTag: app.sourceIPTag(for: connection.metadata.sourceIP),
                                backendKind: app.selectedProfile?.kind,
                                proxyGroups: selectableProxyGroups(for: connection),
                                proxyItem: app.proxyItem(named:),
                                selectProxy: selectProxy(group:proxy:)
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await app.closeConnection(connection.id) }
                                } label: {
                                    Label("Close", systemImage: "xmark.circle")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    rawJSONConnection = connection
                                } label: {
                                    Label("JSON", systemImage: "curlybraces")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                } header: {
                    ConnectionsSectionHeader(
                        visibleCount: filteredConnections.count,
                        totalCount: live.connections.connections.count
                    )
                }
            }
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.bottom, 72, for: .scrollContent)
            .searchable(
                text: $filter.query,
                placement: .toolbar,
                prompt: "Search connections"
            )
            .toolbar {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    AutoReorderTitleButton(isOn: autoReorder) {
                        autoReorder.toggle()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Close All", systemImage: "xmark.circle", role: .destructive) {
                        Task { await app.closeAllConnections() }
                    }
                }
            }
            .toolbarBackground(.visible, for: .bottomBar)
            .sheet(item: $rawJSONConnection) { connection in
                ConnectionRawJSONView(connection: connection)
            }
            .onAppear {
                refreshConnectionOrder()
            }
            .onChange(of: live.connections.connections.map(\.id)) { _, _ in
                refreshConnectionOrder()
            }
            .onChange(of: autoReorder) { _, isAutoReorder in
                if isAutoReorder {
                    connectionOrder = live.connections.connections.map(\.id)
                } else {
                    refreshConnectionOrder()
                }
            }
        }
    }

    private var filteredConnections: [ConnectionInfo] {
        orderedConnections.filter { connection in
            filter.matches(
                connection,
                sourceIPTag: app.sourceIPTag(for: connection.metadata.sourceIP)
            )
        }
    }

    private var sourceIPFilterOptions: [ConnectionSourceFilterOption] {
        let sourceIPs = app.currentSourceIPs(from: live.connections.connections)
        let sourceIPOptions = sourceIPs.map { sourceIP in
            if let tag = app.sourceIPTag(for: sourceIP) {
                return ConnectionSourceFilterOption(title: tag.backendNameForDisplay, value: tag)
            }
            return ConnectionSourceFilterOption(title: sourceIP, value: sourceIP)
        }
        let tagOptions = app.sourceIPTags.map { tag in
            ConnectionSourceFilterOption(
                title: tag.tag.backendNameForDisplay,
                value: tag.tag
            )
        }
        return (tagOptions + sourceIPOptions).stableUniqueSourceFilterOptions
    }

    private var orderedConnections: [ConnectionInfo] {
        let connections = live.connections.connections
        guard !autoReorder else { return connections }
        let pairs = connections.map { ($0.id, $0) }
        let connectionsByID = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        let orderedIDs = Set(connectionOrder)
        return connectionOrder.compactMap { connectionsByID[$0] }
            + connections.filter { !orderedIDs.contains($0.id) }
    }

    private func refreshConnectionOrder() {
        let ids = live.connections.connections.map(\.id)
        guard !autoReorder else {
            connectionOrder = ids
            return
        }
        let liveIDs = Set(ids)
        var orderedIDs = connectionOrder.filter { liveIDs.contains($0) }
        let keptIDs = Set(orderedIDs)
        orderedIDs.append(contentsOf: ids.filter { !keptIDs.contains($0) })
        connectionOrder = orderedIDs
    }

    private func selectableProxyGroups(for connection: ConnectionInfo) -> [ProxyItem] {
        let chainNames = Set(connection.displayChains)
        return app.proxyCollection.groups.filter { group in
            chainNames.contains(group.name) && !group.all.isEmpty
        }
    }

    private func selectProxy(group: String, proxy: String) {
        Task { await app.selectProxy(group: group, proxy: proxy) }
    }
}

struct AutoReorderTitleButton: View {
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Connections")
                    .font(.headline)
                Image(systemName: isOn ? "stop.circle" : "play.circle")
                    .font(.headline)
                    .foregroundStyle(isOn ? Color.orange : Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Stop auto reorder" : "Start auto reorder")
        .accessibilityHint("Toggles connection auto reorder")
    }
}

struct ConnectionSourceFilterOption: Identifiable, Hashable {
    var id: String { value }
    var title: String
    var value: String
}

struct ConnectionSourceFilterMenu: View {
    @Binding var selection: String
    var options: [ConnectionSourceFilterOption]

    var body: some View {
        Picker("Source IP / Tag", selection: $selection) {
            Text("All")
                .tag("")
            ForEach(options) { option in
                Text(verbatim: option.title)
                    .tag(option.value)
            }
        }
        .disabled(options.isEmpty)
    }
}

struct ConnectionsSectionHeader: View {
    var visibleCount: Int
    var totalCount: Int

    var body: some View {
        HStack {
            Spacer()
            Text("\(visibleCount)/\(totalCount)")
                .monospacedDigit()
        }
    }
}

struct ConnectionRow: View {
    var connection: ConnectionInfo
    var sourceIPTag: String?
    var backendKind: BackendKind?
    var proxyGroups: [ProxyItem]
    var proxyItem: (String) -> ProxyItem?
    var selectProxy: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConnectionTitleLine(connection: connection)

            HStack(spacing: 6) {
                ConnectionSourceIPTag(
                    sourceIP: connection.metadata.sourceIP,
                    tag: sourceIPTag
                )
                ConnectionMetadataTag(value: connection.metadata.network, fallback: "network n/a")
                ConnectionMetadataTag(value: connection.metadata.type, fallback: "type n/a")
            }

            ConnectionChainLine(connection: connection)

            if !proxyGroups.isEmpty {
                ConnectionProxySelector(
                    groups: proxyGroups,
                    proxyItem: proxyItem,
                    selectProxy: selectProxy
                )
            }

            ConnectionTrafficLine(connection: connection, backendKind: backendKind)
        }
        .padding(.vertical, 3)
    }
}

struct ConnectionTitleLine: View {
    var connection: ConnectionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: connection.title.backendNameForDisplay)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if connection.isIPOnly {
                    Text("IP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            if let subtitle = connection.subtitle {
                Text(verbatim: subtitle.backendNameForDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct ConnectionSourceIPTag: View {
    var sourceIP: String?
    var tag: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "network")
                .accessibilityHidden(true)
            if let tag {
                Text(verbatim: tag.backendNameForDisplay)
                    .bold()
                    .lineLimit(1)
            } else {
                Text(verbatim: normalizedSourceIP)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private var normalizedSourceIP: String {
        let trimmed = sourceIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "source n/a" : trimmed
    }
}

struct SourceIPTagsInlineEditor: View {
    @Environment(AppModel.self) private var app
    var sourceIPs: [String]

    var body: some View {
        DisclosureGroup {
            if sourceIPs.isEmpty {
                Label("No Source IPs", systemImage: "tag.slash")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sourceIPs, id: \.self) { sourceIP in
                    SourceIPTagEditorRow(
                        sourceIP: sourceIP,
                        initialTag: app.sourceIPTag(for: sourceIP) ?? ""
                    )
                }
            }
        } label: {
            Label("Source IP Tags", systemImage: "tag")
        }
    }
}

struct SourceIPTagEditorRow: View {
    @Environment(AppModel.self) private var app
    var sourceIP: String
    @State private var tag: String

    init(sourceIP: String, initialTag: String) {
        self.sourceIP = sourceIP
        self._tag = State(initialValue: initialTag)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: sourceIP)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                TextField("Tag", text: $tag)
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        app.setSourceIPTag(tag, for: sourceIP)
                    }
                    .onChange(of: tag) { _, newTag in
                        app.setSourceIPTag(newTag, for: sourceIP)
                    }

                if !tag.isEmpty {
                    Button("Clear", systemImage: "xmark.circle") {
                        tag = ""
                        app.removeSourceIPTag(for: sourceIP)
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Clear tag for \(sourceIP)")
                }
            }
        }
        .onChange(of: sourceIP) { _, _ in
            tag = app.sourceIPTag(for: sourceIP) ?? ""
        }
    }
}

struct ConnectionMetadataTag: View {
    var value: String?
    var fallback: String

    var body: some View {
        Text(verbatim: normalizedValue.backendNameForDisplay)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    private var normalizedValue: String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct ConnectionChainLine: View {
    var connection: ConnectionInfo

    var body: some View {
        if connection.displayChains.isEmpty {
            Label("outbound n/a", systemImage: "arrow.triangle.branch")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                ForEach(displayedChains.indices, id: \.self) { index in
                    let chain = displayedChains[index]
                    Text(verbatim: chain.backendNameForDisplay)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
                if hiddenChainCount > 0 {
                    Text("+\(hiddenChainCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var displayedChains: [String] {
        Array(connection.displayChains.prefix(3))
    }

    private var hiddenChainCount: Int {
        max(0, connection.displayChains.count - displayedChains.count)
    }
}

struct ConnectionProxySelector: View {
    var groups: [ProxyItem]
    var proxyItem: (String) -> ProxyItem?
    var selectProxy: (String, String) -> Void

    var body: some View {
        Menu {
            ForEach(groups) { group in
                Section {
                    ForEach(group.all, id: \.self) { proxyName in
                        Button {
                            selectProxy(group.name, proxyName)
                        } label: {
                            proxyButtonLabel(proxyName, group: group)
                        }
                    }
                } header: {
                    Text(verbatim: group.displayName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .accessibilityHidden(true)
                Text(verbatim: selectionSummary)
                    .lineLimit(1)
            }
            .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel("Select proxy")
    }

    private var selectionSummary: String {
        guard groups.count == 1, let group = groups.first else {
            return "\(groups.count) proxy groups"
        }
        let selected = group.now.flatMap { proxyItem($0)?.displayName ?? $0.backendNameForDisplay }
        return "\(group.displayName): \(selected ?? "none")"
    }

    @ViewBuilder
    private func proxyButtonLabel(_ proxyName: String, group: ProxyItem) -> some View {
        let displayName = proxyItem(proxyName)?.displayName ?? proxyName.backendNameForDisplay
        if proxyName == group.now {
            Label {
                Text(verbatim: displayName)
            } icon: {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
        } else {
            Text(verbatim: displayName)
        }
    }
}

struct ConnectionTrafficLine: View {
    var connection: ConnectionInfo
    var backendKind: BackendKind?

    @ViewBuilder
    var body: some View {
        if backendKind == .surge {
            if let rule = normalizedRule {
                connectionRule(rule)
            }
        } else {
            HStack(spacing: 12) {
                ConnectionIconText(systemImage: "arrow.up", title: ByteFormat.bytes(connection.upload))
                ConnectionIconText(
                    systemImage: "arrow.down", title: ByteFormat.bytes(connection.download))
                if let rule = normalizedRule {
                    connectionRule(rule)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var normalizedRule: String? {
        let rule = connection.rule?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return rule.isEmpty ? nil : rule
    }

    private func connectionRule(_ rule: String) -> some View {
        ConnectionIconText(systemImage: "flag", title: rule.backendNameForDisplay)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct ConnectionIconText: View {
    var systemImage: String
    var title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .lineLimit(1)
        }
    }
}

private extension Array where Element == ConnectionSourceFilterOption {
    var stableUniqueSourceFilterOptions: [ConnectionSourceFilterOption] {
        var seen: Set<String> = []
        return filter { option in
            guard !option.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return seen.insert(option.value).inserted
        }
    }
}

struct ConnectionRawJSONView: View {
    @Environment(\.dismiss) private var dismiss
    var connection: ConnectionInfo

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: connection.rawJSONString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Raw JSON")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
