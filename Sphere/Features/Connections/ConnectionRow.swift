import SwiftUI

struct ConnectionRow: View {
    var connection: ConnectionInfo
    var sourceLabel: String?
    var proxyGroups: [ProxyItem]
    var proxyItem: (String) -> ProxyItem?
    var selectProxy: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConnectionTitleLine(connection: connection)

            HStack(spacing: 6) {
                ConnectionSourceLabel(
                    sourceIP: connection.metadata.sourceIP,
                    label: sourceLabel
                )
                if let network = visibleNetwork {
                    ConnectionMetadataTag(value: network, fallback: "")
                }
                ConnectionMetadataTag(
                    value: connection.metadata.type,
                    fallback: "type n/a"
                )
            }

            ConnectionChainLine(connection: connection)

            if !proxyGroups.isEmpty {
                ConnectionProxySelector(
                    groups: proxyGroups,
                    proxyItem: proxyItem,
                    selectProxy: selectProxy
                )
            }

            ConnectionTrafficLine(connection: connection)
        }
        .padding(.vertical, 3)
    }

    private var visibleNetwork: String? {
        let network = connection.metadata.network?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let network, !network.isEmpty else { return nil }
        let normalized = network.lowercased()
        return normalized == "n/a" || normalized == "network n/a" ? nil : network
    }
}
