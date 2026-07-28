import SwiftUI

struct SurgeDeviceRow: View {
    var device: SurgeDevice
    var showsDisclosureIndicator: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(verbatim: device.displayName.backendNameForDisplay)
                            .bold()
                        Text(verbatim: device.displayIPAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: iconName)
                        .foregroundStyle(device.hasActiveRouting ? Color.accentColor : .secondary)
                }

                Spacer()

                if showsDisclosureIndicator {
                    RowDisclosureIndicator()
                }
            }

            LabeledContent("Mode", value: device.modeDescription)
            LabeledContent(
                "Connections",
                value: "\(device.activeConnections) active · \(device.totalConnections) total"
            )

            if let dhcp = device.dhcp,
                let lastSeen = dhcp.lastSeen,
                !lastSeen.isEmpty {
                LabeledContent("DHCP Last Seen") {
                    SurgeDeviceLastSeenText(dhcp: dhcp)
                }
            }
        }
        .font(.subheadline)
        .padding(.vertical, 3)
        .contentShape(.rect)
    }

    private var iconName: String {
        if device.dhcp?.waitingToReconnect == true {
            return "arrow.trianglehead.2.clockwise.rotate.90"
        }
        if device.hasActiveRouting {
            return "network"
        }
        return "externaldrive"
    }
}

private extension SurgeDevice {
    var hasActiveRouting: Bool {
        hasProxyConnection || hasTCPConnection || dhcp?.shouldHandledBySurge == true
    }
}
