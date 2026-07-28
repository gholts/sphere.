import Foundation

nonisolated struct SurgeRequestsPayload: Decodable, Equatable, Sendable {
    var connections: [ConnectionInfo]

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        let requests =
            [
                value.array(for: "requests"),
                value.array(for: "active"),
                value.array(for: "recent"),
                value.array(for: "connections"),
                value.arrayValue,
            ]
            .first { !$0.isEmpty } ?? []
        connections = requests.compactMap(Self.connection(from:))
    }

    private static func connection(from value: JSONValue) -> ConnectionInfo? {
        guard case .object = value,
            let id =
                value.string(for: "id", "request_id", "requestID")
                ?? value.int(for: "id").map(String.init)
        else {
            return nil
        }
        let requestURL = value.string(for: "url", "URL")
        let host =
            value.string(for: "host", "hostname", "domain")
            ?? requestURL.flatMap(Self.host(from:))
        let metadata = ConnectionMetadata(
            network: value.string(for: "network", "protocol"),
            type: value.string(for: "type", "request_type", "method"),
            sourceIP: value.string(
                for: "sourceIP",
                "source_ip",
                "sourceAddress",
                "source_address",
                "client"
            ),
            destinationIP: value.string(
                for: "destinationIP",
                "destination_ip",
                "remoteAddress",
                "remote_address",
                "address",
                "ip"
            ),
            host: host,
            process: value.string(
                for: "process",
                "processName",
                "process_name",
                "processPath"
            )
        )
        let policy =
            value.string(
                for: "policyName",
                "policy",
                "outbound",
                "proxy"
            ) ?? ""
        return ConnectionInfo(
            id: id,
            metadata: metadata,
            upload: Int64(
                value.int(
                    for: "outBytes",
                    "upload",
                    "uploadBytes",
                    "upload_bytes"
                ) ?? 0
            ),
            download: Int64(
                value.int(
                    for: "inBytes",
                    "download",
                    "downloadBytes",
                    "download_bytes"
                ) ?? 0
            ),
            start: value.string(
                for: "start",
                "created",
                "startTime",
                "start_time"
            ),
            chains: policy.isEmpty ? [] : [policy],
            rule: value.string(for: "rule", "ruleName", "rule_name"),
            rulePayload: requestURL
                ?? value.string(
                    for: "rulePayload",
                    "rule_payload",
                    "ruleValue"
                )
        )
    }

    private static func host(from rawURL: String) -> String? {
        URLComponents(string: rawURL)?.host
    }
}
