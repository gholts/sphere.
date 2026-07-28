import SwiftUI

struct SurgeDeviceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var name: String
    @State private var address: String
    @State private var shouldHandledBySurge: Bool
    @State private var isSaving = false
    @State private var isShowingSaveError = false
    @State private var saveErrorMessage = ""

    private let device: SurgeDevice

    init(device: SurgeDevice) {
        self.device = device
        _name = State(initialValue: device.dhcp?.displayName ?? device.name)
        _address = State(
            initialValue: device.dhcp?.assignedIP
                ?? device.dhcp?.currentIP
                ?? device.displayIPAddress
        )
        _shouldHandledBySurge = State(
            initialValue: device.dhcp?.shouldHandledBySurge ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    LabeledContent("Name") {
                        TextField("Name", text: $name)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                    }
                    LabeledContent("IP") {
                        TextField("IP", text: $address)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if let physicalAddress = device.editablePhysicalAddress {
                        LabeledContent("MAC Address") {
                            Text(verbatim: physicalAddress)
                        }
                    }
                    if let vendor = device.vendor, !vendor.isEmpty {
                        LabeledContent("Vendor") {
                            Text(verbatim: vendor)
                        }
                    }
                }

                Section("Routing") {
                    Toggle("Handled by Surge", isOn: $shouldHandledBySurge)
                }
            }
            .navigationTitle("Device Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save", action: save)
                        .disabled(
                            isSaving
                                || device.editablePhysicalAddress == nil
                                || !hasChanges
                        )
                }
            }
            .alert("Unable to Save Device", isPresented: $isShowingSaveError) {
                Button("OK", action: dismissSaveError)
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private var hasChanges: Bool {
        name.trimmed != (device.dhcp?.displayName ?? device.name).trimmed
            || address.trimmed
                != (device.dhcp?.assignedIP
                    ?? device.dhcp?.currentIP
                    ?? device.displayIPAddress).trimmed
            || shouldHandledBySurge
                != (device.dhcp?.shouldHandledBySurge ?? false)
    }

    private func save() {
        guard let physicalAddress = device.editablePhysicalAddress else { return }
        isSaving = true
        Task {
            let outcome = await app.updateDevice(
                SurgeDevice.Update(
                    physicalAddress: physicalAddress,
                    name: name.trimmed,
                    address: address.trimmed,
                    shouldHandledBySurge: shouldHandledBySurge
                )
            )
            isSaving = false
            if let errorMessage = outcome.errorMessage {
                saveErrorMessage = errorMessage
                isShowingSaveError = true
            } else {
                dismiss()
            }
        }
    }

    private func dismissSaveError() {
        isShowingSaveError = false
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
