import SwiftUI

struct SurgeDeviceLastSeenText: View {
    var dhcp: SurgeDevice.DHCP

    var body: some View {
        if let date = dhcp.lastSeenDate {
            if dhcp.prefersRelativeLastSeen(referenceDate: .now) {
                Text(date, style: .relative)
            } else {
                Text(
                    date,
                    format: .dateTime
                        .year()
                        .month(.abbreviated)
                        .day()
                        .hour()
                        .minute()
                )
            }
        } else if let lastSeen = dhcp.lastSeen {
            Text(verbatim: lastSeen)
        }
    }
}
