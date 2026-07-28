import SwiftUI

struct SurgeMITMCertificateShareView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var profileID: UUID
    @State private var fileURL: URL?
    @State private var failureMessage: String?

    init(profileID: UUID, fileURL: URL?) {
        self.profileID = profileID
        _fileURL = State(initialValue: fileURL)
    }

    var body: some View {
        Group {
            if let fileURL {
                FileShareSheet(fileURL: fileURL)
            } else {
                VStack(spacing: 16) {
                    if failureMessage == nil {
                        ProgressView()
                            .controlSize(.large)
                            .accessibilityLabel("Preparing MITM CA certificate")
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                    }

                    VStack(spacing: 8) {
                        Text(failureMessage == nil ? "Preparing Certificate" : "Preparation Failed")
                            .font(.headline)
                        Text(
                            failureMessage
                                ?? "Downloading MITM CA certificate. Keep app open."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }

                    if failureMessage != nil {
                        Button("OK", action: dismiss.callAsFunction)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .presentationDetents(
            fileURL == nil
                ? [.height(failureMessage == nil ? 220 : 250)]
                : [.large]
        )
        .interactiveDismissDisabled(fileURL == nil && failureMessage == nil)
        .task {
            await prepareCertificate()
        }
    }

    private func prepareCertificate() async {
        guard fileURL == nil else { return }
        guard app.selectedProfileID == profileID else {
            failureMessage = "Selected Surge profile changed."
            return
        }

        do {
            fileURL = try await app.prepareSurgeMITMCertificate()
        } catch {
            failureMessage =
                app.selectedProfileID == profileID
                ? error.localizedDescription
                : "Selected Surge profile changed."
        }
    }
}
