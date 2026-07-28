import SwiftUI

struct ConnectionTitleLine: View {
    var connection: ConnectionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: connection.title.backendNameForDisplay)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let subtitle = connection.subtitle {
                Text(verbatim: subtitle.backendNameForDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
