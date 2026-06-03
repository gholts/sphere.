import Foundation

nonisolated struct ConnectionMetadata: Codable, Equatable, Sendable {
    var network: String?
    var type: String?
    var sourceIP: String?
    var destinationIP: String?
    var host: String?
    var process: String?
}

nonisolated struct ConnectionInfo: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var metadata: ConnectionMetadata
    var upload: Int64
    var download: Int64
    var start: String?
    var chains: [String]
    var rule: String?
    var rulePayload: String?

    var outbound: String {
        chains.first ?? rule ?? ""
    }

    var title: String {
        metadata.host.nonEmptyConnectionValue
            ?? metadata.destinationIP.nonEmptyConnectionValue
            ?? id
    }

    var subtitle: String? {
        guard let host = metadata.host.nonEmptyConnectionValue,
            let destinationIP = metadata.destinationIP.nonEmptyConnectionValue,
            host != destinationIP
        else {
            return metadata.process.nonEmptyConnectionValue
        }
        return destinationIP
    }

    var isIPOnly: Bool {
        metadata.host.nonEmptyConnectionValue == nil
            && metadata.destinationIP.nonEmptyConnectionValue != nil
    }

    var displayChains: [String] {
        if !chains.isEmpty { return chains }
        return outbound.nonEmptyConnectionValue.map { [$0] } ?? []
    }

    var rawJSONString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }

    var searchableValues: [String] {
        [
            id,
            metadata.network,
            metadata.type,
            metadata.sourceIP,
            metadata.destinationIP,
            metadata.host,
            metadata.process,
            outbound,
            rule,
            rulePayload,
        ].compactMap(\.nonEmptyConnectionValue)
            + chains
    }
}

nonisolated struct ConnectionsSnapshot: Codable, Equatable, Sendable {
    var uploadTotal: Int64?
    var downloadTotal: Int64?
    var connections: [ConnectionInfo]
    var memory: Int?

    init(
        uploadTotal: Int64?,
        downloadTotal: Int64?,
        connections: [ConnectionInfo],
        memory: Int? = nil
    ) {
        self.uploadTotal = uploadTotal
        self.downloadTotal = downloadTotal
        self.connections = connections
        self.memory = memory
    }
}

nonisolated struct ConnectionFilter: Equatable, Sendable {
    var query = ""
    var sourceIP = ""
    var outbound = ""
    var minimumDownloadBytes: Int64 = 0

    var isEmpty: Bool {
        query.trimmedConnectionValue.isEmpty
            && sourceIP.trimmedConnectionValue.isEmpty
            && outbound.trimmedConnectionValue.isEmpty
            && minimumDownloadBytes == 0
    }

    mutating func reset() {
        query = ""
        sourceIP = ""
        outbound = ""
        minimumDownloadBytes = 0
    }

    func matches(_ connection: ConnectionInfo) -> Bool {
        matches(connection, sourceIPTag: nil)
    }

    func matches(_ connection: ConnectionInfo, sourceIPTag: String?) -> Bool {
        let trimmedQuery = query.trimmedConnectionValue
        let queryMatches =
            trimmedQuery.isEmpty
            || searchableValues(for: connection, sourceIPTag: sourceIPTag).contains {
                $0.localizedStandardContains(trimmedQuery)
            }
        let trimmedSourceIP = sourceIP.trimmedConnectionValue
        let sourceMatches =
            trimmedSourceIP.isEmpty
            || [connection.metadata.sourceIP, sourceIPTag].compactMap(\.nonEmptyConnectionValue)
                .contains {
                    $0.localizedStandardContains(trimmedSourceIP)
                }
        let trimmedOutbound = outbound.trimmedConnectionValue
        let outboundMatches =
            trimmedOutbound.isEmpty
            || connection.displayChains.contains {
                $0.localizedStandardContains(trimmedOutbound)
            }
            || (connection.rule ?? "").localizedStandardContains(trimmedOutbound)
        return queryMatches && sourceMatches && outboundMatches
            && connection.download >= minimumDownloadBytes
    }

    private func searchableValues(for connection: ConnectionInfo, sourceIPTag: String?) -> [String] {
        if let normalizedSourceIPTag = sourceIPTag.nonEmptyConnectionValue {
            return connection.searchableValues + [normalizedSourceIPTag]
        }
        return connection.searchableValues
    }
}

private extension Optional where Wrapped == String {
    nonisolated var nonEmptyConnectionValue: String? {
        switch self {
        case .some(let value):
            return value.nonEmptyConnectionValue
        case .none:
            return nil
        }
    }
}

private extension String {
    nonisolated var nonEmptyConnectionValue: String? {
        let trimmed = trimmedConnectionValue
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated var trimmedConnectionValue: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
