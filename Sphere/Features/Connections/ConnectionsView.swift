import SwiftUI

struct ConnectionsView: View {
    @Environment(AppModel.self) private var app
    @Environment(LiveState.self) private var live
    @State private var sheetPresentation: ConnectionsSheetPresentation?
    @State private var handledNavigationRequestID: UUID?
    @State private var isConfirmingCloseAll = false

    var body: some View {
        NavigationStack {
            List {
                Section("Live") {
                    AdaptiveStatRows(metrics: liveMetrics)
                    if app.selectedProfile?.kind.supportsSourceIPTags == true {
                        SourceIPTagsInlineEditor(
                            sourceIPs: app.currentSourceIPs(
                                from: live.connections.connections
                            )
                        )
                    }
                }

                Button {
                    sheetPresentation = .connections
                } label: {
                    Label("Show Connections", systemImage: "list.bullet")
                }

                Button(role: .destructive) {
                    isConfirmingCloseAll = true
                } label: {
                    Label {
                        Text("Close All")
                    } icon: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                    }
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

                if app.selectedProfile?.kind.supportsDeviceManagement == true {
                    SurgeDevicesSection { device in
                        sheetPresentation = .device(device)
                    }
                }
            }
            .backendPageToolbar(tab: .connections)
            .refreshable {
                await app.refreshConnections(source: .pullToRefresh)
            }
            .sheet(item: $sheetPresentation) { presentation in
                switch presentation {
                case .connections:
                    ConnectionsSheetView()
                        .environment(app)
                        .environment(live)
                case .device(let device):
                    SurgeDeviceEditorView(device: device)
                        .environment(app)
                }
            }
            .onChange(of: app.navigationRequest) { _, request in
                handleNavigationRequest(request)
            }
            .onAppear {
                handleNavigationRequest(app.navigationRequest)
            }
        }
    }

    private var liveMetrics: [StatMetric] {
        var metrics = [
            StatMetric(title: "Active", value: "\(live.connections.connections.count)"),
            StatMetric(title: "Uploaded", value: ByteFormat.bytes(live.connections.uploadTotal)),
            StatMetric(title: "Downloaded", value: ByteFormat.bytes(live.connections.downloadTotal)),
        ]
        if app.selectedProfile?.kind.supportsDeviceManagement == true {
            metrics.append(StatMetric(title: "Devices", value: "\(live.devices.count)"))
        }
        return metrics
    }

    private func handleNavigationRequest(_ request: AppNavigationRequest?) {
        guard let request, handledNavigationRequestID != request.id else { return }
        switch request.destination {
        case .connectionsList:
            sheetPresentation = .connections
            handledNavigationRequestID = request.id
        case .tab(.connections):
            sheetPresentation = nil
            handledNavigationRequestID = request.id
        default:
            break
        }
    }
}
