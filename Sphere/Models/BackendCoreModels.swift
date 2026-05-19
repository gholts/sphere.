import Foundation

nonisolated enum LogLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case debug
    case info
    case warning
    case error

    var id: String { rawValue }
}

nonisolated enum ClashMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case rule = "Rule"
    case global = "Global"
    case direct = "Direct"

    var id: String { rawValue }

    nonisolated var mihomoValue: String { rawValue.lowercased() }

    nonisolated init?(mihomoValue: String) {
        guard
            let value = Self.allCases.first(where: {
                $0.rawValue.caseInsensitiveCompare(mihomoValue) == .orderedSame
            })
        else {
            return nil
        }
        self = value
    }
}

nonisolated struct BackendOverview: Codable, Equatable, Sendable {
    var version: String
    var uptime: TimeInterval?
    var memoryBytes: Int?
    var uploadBytesPerSecond: Int?
    var downloadBytesPerSecond: Int?
    var activeConnections: Int?

    static let empty = Self(
        version: "Unknown",
        uptime: nil,
        memoryBytes: nil,
        uploadBytesPerSecond: nil,
        downloadBytesPerSecond: nil,
        activeConnections: nil
    )

    enum CodingKeys: String, CodingKey {
        case version
        case uptime
        case memoryBytes
        case uploadBytesPerSecond
        case downloadBytesPerSecond
        case activeConnections
        case memoryKB
        case uploadKBps
        case downloadKBps
    }

    init(
        version: String,
        uptime: TimeInterval?,
        memoryBytes: Int?,
        uploadBytesPerSecond: Int?,
        downloadBytesPerSecond: Int?,
        activeConnections: Int?
    ) {
        self.version = version
        self.uptime = uptime
        self.memoryBytes = memoryBytes
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.activeConnections = activeConnections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "Unknown"
        uptime = try container.decodeIfPresent(TimeInterval.self, forKey: .uptime)
        memoryBytes =
            try container.decodeIfPresent(Int.self, forKey: .memoryBytes)
            ?? container.decodeIfPresent(Int.self, forKey: .memoryKB)
        uploadBytesPerSecond =
            try container.decodeIfPresent(Int.self, forKey: .uploadBytesPerSecond)
            ?? container.decodeIfPresent(Int.self, forKey: .uploadKBps)
        downloadBytesPerSecond =
            try container.decodeIfPresent(Int.self, forKey: .downloadBytesPerSecond)
            ?? container.decodeIfPresent(Int.self, forKey: .downloadKBps)
        activeConnections = try container.decodeIfPresent(Int.self, forKey: .activeConnections)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(uptime, forKey: .uptime)
        try container.encodeIfPresent(memoryBytes, forKey: .memoryBytes)
        try container.encodeIfPresent(uploadBytesPerSecond, forKey: .uploadBytesPerSecond)
        try container.encodeIfPresent(downloadBytesPerSecond, forKey: .downloadBytesPerSecond)
        try container.encodeIfPresent(activeConnections, forKey: .activeConnections)
    }
}

nonisolated struct MihomoVersionPayload: Decodable, Equatable, Sendable {
    var version: String

    enum CodingKeys: String, CodingKey {
        case version
    }

    init(version: String) {
        self.version = Self.clean(version)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = Self.clean(try container.decodeIfPresent(String.self, forKey: .version) ?? "")
    }

    private static func clean(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

nonisolated struct MihomoModePayload: Decodable, Equatable, Sendable {
    var mode: ClashMode?

    enum CodingKeys: String, CodingKey {
        case mode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(String.self, forKey: .mode).flatMap(
            ClashMode.init(mihomoValue:))
    }
}

nonisolated struct MemorySnapshot: Codable, Equatable, Sendable {
    var inuse: Int?
}

nonisolated struct TrafficSnapshot: Codable, Equatable, Sendable {
    var up: Int
    var down: Int
}

nonisolated struct ProxyDelayPayload: Decodable, Equatable, Sendable {
    var delay: Int?

    enum CodingKeys: String, CodingKey {
        case delay
    }
}
