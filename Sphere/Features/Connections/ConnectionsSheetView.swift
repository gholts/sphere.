import SwiftUI

struct ConnectionsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(LiveState.self) private var live
    @State private var filter = ConnectionFilter()
    @State private var autoReorder = true
    @State private var connectionOrder: [String] = []
    @State private var rawJSONConnection: ConnectionInfo?
    @State private var isSearchPresented = false
    @State private var isConfirmingCloseAll = false
    @FocusState private var isOutboundFilterFocused: Bool

    var body: some View {
        NavigationStack {
            let connections = live.connections.connections
            let sourceNames = sourceNameLookup(for: connections)
            let filteredConnections = filteredConnections(
                in: connections,
                sourceNames: sourceNames
            )
            List {
                Section("Filters") {
                    ConnectionSourceFilterMenu(
                        selection: $filter.sourceIP,
                        title: sourceFilterTitle,
                        options: sourceIPFilterOptions(
                            connections: connections,
                            sourceNames: sourceNames
                        )
                    )
                    TextField("Outbound / Rule", text: $filter.outbound)
                        .textInputAutocapitalization(.never)
                        .focused($isOutboundFilterFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isOutboundFilterFocused = false
                        }
                    Stepper(
                        value: $filter.minimumDownloadBytes,
                        in: 0...1_000_000_000,
                        step: 1024
                    ) {
                        Text(
                            "Min download: \(ByteFormat.bytes(filter.minimumDownloadBytes))"
                        )
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
                            message: filter.isEmpty
                                ? "No active connections."
                                : "Change filters.",
                            systemImage: filter.isEmpty
                                ? "network.slash"
                                : "line.3.horizontal.decrease.circle"
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredConnections) { connection in
                            ConnectionRow(
                                connection: connection,
                                sourceLabel: sourceName(
                                    for: connection.metadata.sourceIP,
                                    in: sourceNames
                                ),
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
                        totalCount: connections.count
                    )
                }
            }
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $filter.query,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search connections"
            )
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    AutoReorderTitleButton(isOn: autoReorder) {
                        autoReorder.toggle()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(
                        "Close All",
                        systemImage: "xmark.circle",
                        role: .destructive
                    ) {
                        isConfirmingCloseAll = true
                    }
                    .confirmationDialog(
                        "Close All Connections?",
                        isPresented: $isConfirmingCloseAll,
                        titleVisibility: .visible
                    ) {
                        Button("Close All Connections", role: .destructive) {
                            Task { await app.closeAllConnections() }
                        }
                        Button("Cancel", role: .cancel) {
                            isConfirmingCloseAll = false
                        }
                    } message: {
                        Text("Every active backend connection will be closed.")
                    }
                }
            }
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

    private func filteredConnections(
        in connections: [ConnectionInfo],
        sourceNames: [String: String]
    ) -> [ConnectionInfo] {
        orderedConnections(from: connections).filter { connection in
            filter.matches(
                connection,
                sourceName: sourceName(
                    for: connection.metadata.sourceIP,
                    in: sourceNames
                )
            )
        }
    }

    private var sourceFilterTitle: String {
        app.selectedProfile?.kind.supportsDeviceManagement == true
            ? "Source / Device"
            : "Source IP / Tag"
    }

    private func sourceIPFilterOptions(
        connections: [ConnectionInfo],
        sourceNames: [String: String]
    ) -> [ConnectionSourceFilterOption] {
        guard app.selectedProfile?.kind.supportsDeviceManagement == true else {
            let sourceIPOptions = app.currentSourceIPs(
                from: connections
            ).map { sourceIP in
                if let tag = app.sourceIPTag(for: sourceIP) {
                    return ConnectionSourceFilterOption(
                        title: tag.backendNameForDisplay,
                        value: tag
                    )
                }
                return ConnectionSourceFilterOption(
                    title: sourceIP,
                    value: sourceIP
                )
            }
            let tagOptions = app.sourceIPTags.map { tag in
                ConnectionSourceFilterOption(
                    title: tag.tag.backendNameForDisplay,
                    value: tag.tag
                )
            }
            return (tagOptions + sourceIPOptions).stableUniqueSourceFilterOptions
        }

        let sourceIPOptions: [ConnectionSourceFilterOption] =
            connections.compactMap { connection in
                guard
                    let sourceIP = SurgeDevice.normalizedIPAddress(
                        connection.metadata.sourceIP
                    )
                else {
                    return nil
                }
                if let name = sourceName(for: sourceIP, in: sourceNames) {
                    return ConnectionSourceFilterOption(
                        title: "\(name.backendNameForDisplay) · \(sourceIP)",
                        value: name
                    )
                }
                return ConnectionSourceFilterOption(
                    title: sourceIP,
                    value: sourceIP
                )
            }
        return sourceIPOptions.stableUniqueSourceFilterOptions
    }

    private func orderedConnections(from connections: [ConnectionInfo]) -> [ConnectionInfo] {
        guard !autoReorder else { return connections }
        let connectionsByID = Dictionary(
            connections.lazy.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let orderedIDs = Set(connectionOrder)
        return connectionOrder.compactMap { connectionsByID[$0] }
            + connections.filter { !orderedIDs.contains($0.id) }
    }

    private func sourceNameLookup(
        for connections: [ConnectionInfo]
    ) -> [String: String] {
        var checkedAddresses: Set<String> = []
        var sourceNames: [String: String] = [:]
        for connection in connections {
            let sourceAddress = connection.metadata.sourceIP
            guard
                let key = sourceAddressKey(sourceAddress),
                checkedAddresses.insert(key).inserted,
                let name = app.sourceDisplayName(for: sourceAddress)
            else {
                continue
            }
            sourceNames[key] = name
        }
        return sourceNames
    }

    private func sourceName(
        for sourceAddress: String?,
        in sourceNames: [String: String]
    ) -> String? {
        sourceAddressKey(sourceAddress).flatMap { sourceNames[$0] }
    }

    private func sourceAddressKey(_ sourceAddress: String?) -> String? {
        if app.selectedProfile?.kind.supportsDeviceManagement == true {
            return SurgeDevice.normalizedIPAddress(sourceAddress)
        }
        return SourceIPTagStore.normalized(sourceAddress)
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

    private func selectableProxyGroups(
        for connection: ConnectionInfo
    ) -> [ProxyItem] {
        let chainNames = Set(connection.displayChains)
        return app.proxyCollection.groups.filter { group in
            chainNames.contains(group.name) && !group.all.isEmpty
        }
    }

    private func selectProxy(group: String, proxy: String) {
        Task { await app.selectProxy(group: group, proxy: proxy) }
    }
}
