import SwiftUI

struct ProfileWizardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: BackendKind
    @State private var baseURL: String
    @State private var secret: String
    @State private var testResult: ProfileTestResult?
    @State private var isTesting = false
    private let minimumTestingIndicatorDuration: TimeInterval = 0.35
    private let editingProfile: APIProfile?
    private let profileID: UUID
    var canDismiss: Bool

    init(editingProfile: APIProfile? = nil, canDismiss: Bool = false) {
        self.editingProfile = editingProfile
        self.profileID = editingProfile?.id ?? UUID()
        self.canDismiss = canDismiss
        _name = State(initialValue: editingProfile?.name ?? "")
        _kind = State(initialValue: editingProfile?.kind ?? .mihomo)
        _baseURL = State(initialValue: editingProfile?.baseURL ?? "http://127.0.0.1:9090")
        _secret = State(initialValue: editingProfile?.secret ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(BackendKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    TextField("Controller URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("Secret", text: $secret)
                        .textContentType(nil)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !kind.isImplemented {
                        Label("\(kind.title) saved only. Client comes later.", systemImage: "hammer")
                    }

                    Button {
                        Task { await test() }
                    } label: {
                        HStack(spacing: 8) {
                            DisabledAwareActionLabel(
                                title: "Test Connection",
                                systemImage: "antenna.radiowaves.left.and.right",
                                isEnabled: canTestConnection
                            )
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.accentColor)
                                    .transition(.spinnerBadgeAppearance)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.spinnerBadgeAppearance, value: isTesting)
                    }
                    .disabled(!canTestConnection)
                    .allowsHitTesting(!isTesting)

                    Button {
                        saveProfile()
                    } label: {
                        DisabledAwareActionLabel(
                            title: saveButtonTitle,
                            systemImage: "checkmark.circle",
                            isEnabled: canSaveProfile
                        )
                    }
                    .disabled(!canSaveProfile)

                    if let testResult {
                        Label {
                            Text(testResult.message)
                        } icon: {
                            Image(systemName: testResult.systemImage)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(testResult.tint)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(canDismiss ? .inline : .automatic)
            .toolbar {
                if canDismiss {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var profile: APIProfile {
        APIProfile(id: profileID, name: name, kind: kind, baseURL: baseURL, secret: secret)
    }

    private var canTestConnection: Bool {
        kind.isImplemented && !trimmedBaseURL.isEmpty
    }

    private var canSaveProfile: Bool {
        !trimmedName.isEmpty && !trimmedBaseURL.isEmpty
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var navigationTitle: String {
        editingProfile == nil ? "Add Backend" : "Edit Backend"
    }

    private var saveButtonTitle: String {
        editingProfile == nil ? "Save Profile" : "Save Changes"
    }

    func test() async {
        guard !isTesting else { return }
        let startedAt = Date()
        isTesting = true
        let nextResult: ProfileTestResult
        let testedProfile = profile
        do {
            let overview = try await app.testProfile(testedProfile)
            let detectedKind = CoreVersionDisplay.resolvedKind(for: overview.version, fallback: testedProfile.kind)
            kind = detectedKind
            nextResult = .success(CoreVersionDisplay.successMessage(for: overview.version, kind: detectedKind))
        } catch {
            nextResult = .failure(error.localizedDescription)
        }
        await waitForMinimumTestingIndicatorDuration(since: startedAt)
        testResult = nextResult
        isTesting = false
    }

    private func waitForMinimumTestingIndicatorDuration(since startedAt: Date) async {
        let remaining = minimumTestingIndicatorDuration - Date().timeIntervalSince(startedAt)
        guard remaining > 0 else { return }
        try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
    }

    private func saveProfile() {
        if editingProfile == nil {
            app.addProfile(profile)
        } else {
            app.updateProfile(profile)
        }
        if canDismiss {
            dismiss()
        }
    }
}

private struct ProfileTestResult: Equatable {
    enum Status {
        case success
        case failure
    }

    var message: String
    var status: Status

    static func success(_ message: String) -> Self {
        Self(message: message, status: .success)
    }

    static func failure(_ message: String) -> Self {
        Self(message: message, status: .failure)
    }

    var systemImage: String {
        switch status {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch status {
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
}

enum CoreVersionDisplay {
    private static let coreNameTokens = ["mihomo", "sing-box", "singbox", "clash"]

    static func successMessage(for version: String, kind: BackendKind) -> String {
        "OK: \(coreAndVersion(for: version, kind: kind))"
    }

    static func resolvedKind(for version: String, fallback: BackendKind) -> BackendKind {
        guard let detected = BackendKind.detected(fromVersion: version), detected.isImplemented else {
            return fallback
        }
        return detected
    }

    static func coreAndVersion(for version: String, kind: BackendKind) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanVersion = trimmed.isEmpty ? "Unknown" : trimmed
        let lowercased = cleanVersion.lowercased()
        if coreNameTokens.contains(where: lowercased.contains) {
            return cleanVersion
        }
        return "\(kind.title) \(cleanVersion)"
    }
}
