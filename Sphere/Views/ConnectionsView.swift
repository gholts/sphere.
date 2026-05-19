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
        [
            StatMetric(title: "Active", value: "\(live.connections.connections.count)"),
            StatMetric(title: "Uploaded", value: ByteFormat.bytes(live.connections.uploadTotal)),
            StatMetric(title: "Downloaded", value: ByteFormat.bytes(live.connections.downloadTotal)),
        ]
    }
}

struct ConnectionsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(LiveState.self) private var live
    @State private var filter = ConnectionFilter()
    
    var body: some View {
        NavigationStack {
            List {
                Section("Filters") {
                    TextField("Source IP", text: $filter.sourceIP)
                        .textInputAutocapitalization(.never)
                    TextField("Outbound", text: $filter.outbound)
                        .textInputAutocapitalization(.never)
                    Stepper(value: $filter.minimumDownloadBytes, in: 0...1_000_000_000, step: 1024) {
                        Text("Min download: \(ByteFormat.bytes(filter.minimumDownloadBytes))")
                    }
                }
                
                Section("Connections") {
                    if filteredConnections.isEmpty {
                        Text("No matching connections")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredConnections) { connection in
                            ConnectionRow(connection: connection) {
                                Task { await app.closeConnection(connection.id) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        Task { await app.closeAllConnections() }
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .accessibilityLabel("Close all connections")
                }
            }
        }
    }
    
    private var filteredConnections: [ConnectionInfo] {
        live.connections.connections.filter(filter.matches)
    }
}

struct ConnectionRow: View {
    var connection: ConnectionInfo
    var close: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(connection.metadata.host ?? connection.metadata.destinationIP ?? connection.id)
                    .lineLimit(1)
                Spacer()
                Button(role: .destructive, action: close) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close connection")
            }
            
            HStack {
                Text(connection.metadata.sourceIP ?? "source n/a")
                Spacer()
                Text(verbatim: connection.outbound.isEmpty ? "outbound n/a" : connection.outbound.backendNameForDisplay)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            HStack {
                Label(ByteFormat.bytes(connection.upload), systemImage: "arrow.up")
                Label(ByteFormat.bytes(connection.download), systemImage: "arrow.down")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
