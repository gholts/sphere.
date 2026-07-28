import SwiftUI

struct SurgeDevicesSection: View {
    @Environment(LiveState.self) private var live
    var editDevice: (SurgeDevice) -> Void

    var body: some View {
        Section("Devices") {
            if live.devices.isEmpty {
                Label("No managed devices", systemImage: "externaldrive.badge.questionmark")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(live.devices) { device in
                    if device.editablePhysicalAddress == nil {
                        SurgeDeviceRow(
                            device: device,
                            showsDisclosureIndicator: false
                        )
                    } else {
                        Button {
                            editDevice(device)
                        } label: {
                            SurgeDeviceRow(
                                device: device,
                                showsDisclosureIndicator: true
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens Surge device settings")
                    }
                }
            }
        }
    }
}
