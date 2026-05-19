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
}

nonisolated struct ConnectionsSnapshot: Codable, Equatable, Sendable {
    var uploadTotal: Int64?
    var downloadTotal: Int64?
    var connections: [ConnectionInfo]
    var memory: Int?
    
    init(uploadTotal: Int64?, downloadTotal: Int64?, connections: [ConnectionInfo], memory: Int? = nil) {
        self.uploadTotal = uploadTotal
        self.downloadTotal = downloadTotal
        self.connections = connections
        self.memory = memory
    }
}

nonisolated struct ConnectionFilter: Equatable, Sendable {
    var sourceIP = ""
    var outbound = ""
    var minimumDownloadBytes: Int64 = 0
    
    func matches(_ connection: ConnectionInfo) -> Bool {
        let sourceMatches = sourceIP.isEmpty || (connection.metadata.sourceIP ?? "").localizedStandardContains(sourceIP)
        let outboundMatches = outbound.isEmpty || connection.outbound.localizedStandardContains(outbound)
        return sourceMatches && outboundMatches && connection.download >= minimumDownloadBytes
    }
}
