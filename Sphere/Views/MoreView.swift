import SwiftUI
import UIKit

struct MoreView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var live: LiveBackendStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var profileForm: ProfileFormPresentation?
    @State private var coreUpdateDialog: CoreUpdateDialog?

    var body: some View {
        NavigationStack {
            List {
                Section("Backend") {
                    Picker("Profile", selection: profileBinding) {
                        ForEach(app.profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    
                    Button {
                        profileForm = .add
                    } label: {
                        Label("Add Profile", systemImage: "plus.circle")
                    }
                }
                
                Section("Overview") {
                    Picker(selection: modeBinding) {
                        ForEach(ClashMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    } label: {
                        Text("Mode")
                            .foregroundStyle(.secondary)
                    }
                    
                    OverviewRows(overview: live.overview)
                }
                
                if canUpdateCore {
                    Section("Update Core") {
                        ForEach(CoreUpdateChannel.allCases) { channel in
                            Button {
                                startCoreUpdate(channel: channel)
                            } label: {
                                DisabledAwareActionLabel(
                                    title: channel.title,
                                    systemImage: "arrow.down.circle",
                                    isEnabled: !app.isUpdatingCore
                                )
                            }
                            .disabled(app.isUpdatingCore)
                        }
                    }
                }
                
                Section("Tools") {
                    NavigationLink {
                        ConfigEditorView()
                    } label: {
                        Label("Configuration", systemImage: "slider.horizontal.3")
                    }
                    
                    NavigationLink {
                        LogBookView()
                    } label: {
                        Label("Log Book", systemImage: "doc.text.magnifyingglass")
                    }
                }
                
                Section("Profiles") {
                    ForEach(app.profiles) { profile in
                        Button {
                            profileForm = .edit(profile)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                    Text("\(profile.kind.title) · \(profile.baseURL)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete(perform: app.deleteProfiles)
                }
                
            }
            .backendPageToolbar(tab: .more)
            .sheet(item: $profileForm) { form in
                ProfileWizardView(editingProfile: form.editingProfile, canDismiss: true)
                    .environmentObject(app)
            }
            .sheet(item: $coreUpdateDialog) { dialog in
                CoreUpdateDialogView(dialog: dialog)
            }
            .refreshable {
                await app.refreshAll(source: .pullToRefresh)
            }
        }
    }

    private var profileBinding: Binding<UUID?> {
        Binding(
            get: { app.selectedProfileID },
            set: { app.selectProfile($0) }
        )
    }

    private var modeBinding: Binding<ClashMode> {
        Binding(
            get: { app.clashMode },
            set: { mode in Task { await app.updateMode(mode) } }
        )
    }

    private var canUpdateCore: Bool {
        app.selectedProfile?.kind == .mihomo && !live.overview.version.localizedCaseInsensitiveContains("sing-box")
    }

    private func startCoreUpdate(channel: CoreUpdateChannel) {
        coreUpdateDialog = CoreUpdateDialog(channel: channel, phase: .updating)
        Task { @MainActor in
            let report = await app.upgradeCore(channel: channel)
            coreUpdateDialog = CoreUpdateDialog(channel: channel, phase: .finished(report))
        }
    }
}

private struct CoreUpdateDialog: Identifiable, Equatable {
    enum Phase: Equatable {
        case updating
        case finished(CoreUpdateReport)
    }

    var channel: CoreUpdateChannel
    var phase: Phase

    var id: String { channel.id }

    var isUpdating: Bool {
        if case .updating = phase { return true }
        return false
    }

    var title: String {
        switch phase {
        case .updating:
            return "Updating Core"
        case .finished(let report):
            return report.title
        }
    }

    var message: String {
        switch phase {
        case .updating:
            return "\(channel.title) channel. Keep app open."
        case .finished(let report):
            return report.message
        }
    }

    var systemImage: String {
        switch phase {
        case .updating:
            return "arrow.triangle.2.circlepath"
        case .finished(let report):
            return report.systemImage
        }
    }

    var iconStyle: Color {
        switch phase {
        case .updating:
            return .accentColor
        case .finished(let report):
            switch report.status {
            case .success:
                return .green
            case .failure:
                return .red
            case .skipped:
                return .orange
            }
        }
    }
}

private struct CoreUpdateDialogView: View {
    @Environment(\.dismiss) private var dismiss
    var dialog: CoreUpdateDialog

    var body: some View {
        VStack(spacing: 16) {
            icon

            VStack(spacing: 8) {
                Text(dialog.title)
                    .font(.headline)
                Text(dialog.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !dialog.isUpdating {
                Button("OK") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(dialog.isUpdating ? 220 : 250)])
        .interactiveDismissDisabled(dialog.isUpdating)
    }

    @ViewBuilder
    private var icon: some View {
        if dialog.isUpdating {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Updating core")
        } else {
            Image(systemName: dialog.systemImage)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(dialog.iconStyle)
                .accessibilityHidden(true)
        }
    }
}

struct OverviewRows: View {
    var overview: BackendOverview

    var body: some View {
        AdaptiveStatRows(metrics: [
            StatMetric(title: "Version", value: overview.version),
            StatMetric(title: "Memory", value: ByteFormat.memoryBytes(overview.memoryBytes)),
            StatMetric(title: "Upload", value: ByteFormat.speedBytes(overview.uploadBytesPerSecond)),
            StatMetric(title: "Download", value: ByteFormat.speedBytes(overview.downloadBytesPerSecond)),
            StatMetric(title: "Active Connections", value: overview.activeConnections.map(String.init) ?? "n/a"),
        ])
    }
}
