import Foundation

enum LogLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case debug
    case info
    case warning
    case error

    var id: String { rawValue }
}

enum ClashMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case rule = "Rule"
    case global = "Global"
    case direct = "Direct"

    var id: String { rawValue }

    nonisolated var mihomoValue: String { rawValue.lowercased() }

    nonisolated init?(mihomoValue: String) {
        guard let value = Self.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(mihomoValue) == .orderedSame }) else {
            return nil
        }
        self = value
    }
}

struct BackendOverview: Codable, Equatable, Sendable {
    var version: String
    var uptime: TimeInterval?
    var memoryBytes: Int?
    var uploadBytesPerSecond: Int?
    var downloadBytesPerSecond: Int?
    var activeConnections: Int?

    static let empty = BackendOverview(
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
        memoryBytes = try container.decodeIfPresent(Int.self, forKey: .memoryBytes) ?? container.decodeIfPresent(Int.self, forKey: .memoryKB)
        uploadBytesPerSecond = try container.decodeIfPresent(Int.self, forKey: .uploadBytesPerSecond) ?? container.decodeIfPresent(Int.self, forKey: .uploadKBps)
        downloadBytesPerSecond = try container.decodeIfPresent(Int.self, forKey: .downloadBytesPerSecond) ?? container.decodeIfPresent(Int.self, forKey: .downloadKBps)
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

struct ProxyItem: Identifiable, Equatable, Codable, Sendable {
    var id: String { name }
    var name: String
    var type: String
    var now: String?
    var all: [String]
    var udp: Bool?
    var xudp: Bool?
    var fixed: String?
    var icon: String?
    var testUrl: String?
    var dialerProxy: String?
    var providerName: String?
    var hidden: Bool?
    var delay: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case now
        case all
        case udp
        case xudp
        case fixed
        case icon
        case testUrl
        case dialerProxy = "dialer-proxy"
        case providerName = "provider-name"
        case hidden
        case history
        case delay
    }

    init(
        name: String,
        type: String,
        now: String? = nil,
        all: [String] = [],
        udp: Bool? = nil,
        xudp: Bool? = nil,
        fixed: String? = nil,
        icon: String? = nil,
        testUrl: String? = nil,
        dialerProxy: String? = nil,
        providerName: String? = nil,
        hidden: Bool? = nil,
        delay: Int? = nil
    ) {
        self.name = name
        self.type = type
        self.now = now
        self.all = all
        self.udp = udp
        self.xudp = xudp
        self.fixed = fixed
        self.icon = icon
        self.testUrl = testUrl
        self.dialerProxy = dialerProxy
        self.providerName = providerName
        self.hidden = hidden
        self.delay = delay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "Unknown"
        now = try container.decodeIfPresent(String.self, forKey: .now)
        all = try container.decodeIfPresent([String].self, forKey: .all) ?? []
        udp = try container.decodeIfPresent(Bool.self, forKey: .udp)
        xudp = try container.decodeIfPresent(Bool.self, forKey: .xudp)
        fixed = try container.decodeIfPresent(String.self, forKey: .fixed)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        testUrl = try container.decodeIfPresent(String.self, forKey: .testUrl)
        dialerProxy = try container.decodeIfPresent(String.self, forKey: .dialerProxy)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden)
        let history = try container.decodeIfPresent([DelayHistory].self, forKey: .history) ?? []
        delay = try container.decodeIfPresent(Int.self, forKey: .delay) ?? history.last?.delay
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(now, forKey: .now)
        try container.encode(all, forKey: .all)
        try container.encodeIfPresent(udp, forKey: .udp)
        try container.encodeIfPresent(xudp, forKey: .xudp)
        try container.encodeIfPresent(fixed, forKey: .fixed)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(testUrl, forKey: .testUrl)
        try container.encodeIfPresent(dialerProxy, forKey: .dialerProxy)
        try container.encodeIfPresent(providerName, forKey: .providerName)
        try container.encodeIfPresent(hidden, forKey: .hidden)
        try container.encodeIfPresent(delay, forKey: .delay)
    }

    var isGroup: Bool {
        !all.isEmpty
    }

    var metaBadges: [String] {
        var badges: [String] = []
        badges.append(type)
        if udp == true { badges.append("UDP") }
        if xudp == true { badges.append("XUDP") }
        if let fixed, !fixed.isEmpty {
                badges.append("\n\(fixed)")
            } else {
                badges.append("auto")
            }
        if let dialerProxy, !dialerProxy.isEmpty { badges.append("Dialer \(dialerProxy)") }
        return badges
    }
}

struct DelayHistory: Codable, Equatable, Sendable {
    var time: String?
    var delay: Int?
}

struct ProxyCollection: Codable, Equatable, Sendable {
    var proxies: [ProxyItem]
    var groups: [ProxyItem]

    enum CodingKeys: String, CodingKey {
        case proxies
        case groups
    }

    init(proxies: [ProxyItem] = [], groups: [ProxyItem] = []) {
        self.proxies = proxies
        self.groups = groups
    }

    func item(named name: String) -> ProxyItem? {
        proxies.first { $0.name == name } ?? groups.first { $0.name == name }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let cachedGroups = try container.decodeIfPresent([ProxyItem].self, forKey: .groups) {
            proxies = try container.decodeIfPresent([ProxyItem].self, forKey: .proxies) ?? []
            groups = cachedGroups
            return
        }

        let values = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .proxies)
        let orderedProxies = try values.allKeys.map { try values.decode(ProxyItem.self, forKey: $0) }
        proxies = orderedProxies.filter { !$0.isGroup }

        let groupCandidates = orderedProxies.filter(\.isGroup)
        if let global = orderedProxies.first(where: { $0.name == "GLOBAL" }), !global.all.isEmpty {
            let sourceOrder = Dictionary(uniqueKeysWithValues: groupCandidates.enumerated().map { ($0.element.name, $0.offset) })
            let globalOrder = Dictionary(uniqueKeysWithValues: global.all.enumerated().map { ($0.element, $0.offset) })
            groups = groupCandidates.sorted { left, right in
                if left.name == "GLOBAL" { return true }
                if right.name == "GLOBAL" { return false }
                switch (globalOrder[left.name], globalOrder[right.name]) {
                case (.some(let leftIndex), .some(let rightIndex)):
                    return leftIndex < rightIndex
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    return (sourceOrder[left.name] ?? 0) < (sourceOrder[right.name] ?? 0)
                }
            }
        } else {
            groups = groupCandidates
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(proxies, forKey: .proxies)
        try container.encode(groups, forKey: .groups)
    }
}

struct ProxyProvider: Identifiable, Codable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var type: String?
    var vehicleType: String?
    var updatedAt: String?
    var expireAt: Date?
    var usedBytes: Int64?
    var totalBytes: Int64?
    var proxies: [ProxyItem]

    var remainingBytes: Int64? {
        guard let usedBytes, let totalBytes else { return nil }
        return max(0, totalBytes - usedBytes)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case vehicleType
        case updatedAt
        case expireAt
        case usedBytes
        case totalBytes
        case proxies
        case subscriptionInfo
    }

    init(
        name: String,
        type: String? = nil,
        vehicleType: String? = nil,
        updatedAt: String? = nil,
        expireAt: Date? = nil,
        usedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        proxies: [ProxyItem] = []
    ) {
        self.name = name
        self.type = type
        self.vehicleType = vehicleType
        self.updatedAt = updatedAt
        self.expireAt = expireAt
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.proxies = proxies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type)
        vehicleType = try container.decodeIfPresent(String.self, forKey: .vehicleType)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        proxies = try container.decodeIfPresent([ProxyItem].self, forKey: .proxies) ?? []
        let info = try container.decodeIfPresent(SubscriptionInfo.self, forKey: .subscriptionInfo)
        expireAt = try container.decodeIfPresent(Date.self, forKey: .expireAt) ?? info?.expireAt
        usedBytes = try container.decodeIfPresent(Int64.self, forKey: .usedBytes) ?? info?.usedBytes
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? info?.totalBytes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(vehicleType, forKey: .vehicleType)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(expireAt, forKey: .expireAt)
        try container.encodeIfPresent(usedBytes, forKey: .usedBytes)
        try container.encodeIfPresent(totalBytes, forKey: .totalBytes)
        try container.encode(proxies, forKey: .proxies)
    }
}

struct ProviderCollection<T: Decodable & Identifiable & Equatable>: Decodable, Equatable {
    var providers: [T]

    enum CodingKeys: String, CodingKey {
        case providers
    }

    init(providers: [T] = []) {
        self.providers = providers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let values = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .providers)
        providers = try values.allKeys.map { try values.decode(T.self, forKey: $0) }
    }
}

struct SubscriptionInfo: Codable, Equatable, Sendable {
    var upload: Int64?
    var download: Int64?
    var total: Int64?
    var expire: Int64?

    var usedBytes: Int64? {
        switch (upload, download) {
        case (.some(let upload), .some(let download)):
            return upload + download
        case (.some(let upload), nil):
            return upload
        case (nil, .some(let download)):
            return download
        default:
            return nil
        }
    }

    var totalBytes: Int64? { total }

    var remainingBytes: Int64? {
        guard let usedBytes, let total else { return nil }
        return max(0, total - usedBytes)
    }

    var expireAt: Date? {
        guard let expire, expire > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(expire))
    }

    enum CodingKeys: String, CodingKey {
        case upload
        case download
        case total
        case expire
        case upperUpload = "Upload"
        case upperDownload = "Download"
        case upperTotal = "Total"
        case upperExpire = "Expire"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        upload = try container.decodeIfPresent(Int64.self, forKey: .upload) ?? container.decodeIfPresent(Int64.self, forKey: .upperUpload)
        download = try container.decodeIfPresent(Int64.self, forKey: .download) ?? container.decodeIfPresent(Int64.self, forKey: .upperDownload)
        total = try container.decodeIfPresent(Int64.self, forKey: .total) ?? container.decodeIfPresent(Int64.self, forKey: .upperTotal)
        expire = try container.decodeIfPresent(Int64.self, forKey: .expire) ?? container.decodeIfPresent(Int64.self, forKey: .upperExpire)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(upload, forKey: .upload)
        try container.encodeIfPresent(download, forKey: .download)
        try container.encodeIfPresent(total, forKey: .total)
        try container.encodeIfPresent(expire, forKey: .expire)
    }
}

struct MihomoVersionPayload: Decodable, Equatable, Sendable {
    var version: String

    enum CodingKeys: String, CodingKey {
        case version
    }

    init(version: String) {
        self.version = MihomoVersionPayload.clean(version)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = MihomoVersionPayload.clean(try container.decodeIfPresent(String.self, forKey: .version) ?? "")
    }

    private static func clean(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

struct MihomoModePayload: Decodable, Equatable, Sendable {
    var mode: ClashMode?

    enum CodingKeys: String, CodingKey {
        case mode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(String.self, forKey: .mode).flatMap(ClashMode.init(mihomoValue:))
    }
}

struct MemorySnapshot: Codable, Equatable, Sendable {
    var inuse: Int?
}

struct TrafficSnapshot: Codable, Equatable, Sendable {
    var up: Int
    var down: Int
}

struct ProxyDelayPayload: Decodable, Equatable, Sendable {
    var delay: Int?

    enum CodingKeys: String, CodingKey {
        case delay
    }
}

struct RuleItem: Identifiable, Codable, Equatable, Sendable {
    var id: String {
        if let index {
            return "\(index)-\(type)-\(payload)-\(proxy)"
        }
        return "\(type)-\(payload)-\(proxy)"
    }
    var type: String
    var payload: String
    var proxy: String
    var index: Int?

    var isRuleSet: Bool {
        ["ruleset", "rule-set", "rule_set"].contains(normalizedType)
    }

    var isMatch: Bool {
        normalizedType == "match"
    }

    var displayTitle: String {
        if isMatch {
            return "Match"
        }
        let value = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? type : value
    }

    private var normalizedType: String {
        type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    init(type: String, payload: String, proxy: String, index: Int? = nil) {
        self.type = type
        self.payload = payload
        self.proxy = proxy
        self.index = index
    }
}

struct RuleCollection: Codable, Equatable, Sendable {
    var rules: [RuleItem]
}

struct RuleProvider: Identifiable, Codable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var type: String?
    var vehicleType: String?
    var behavior: String?
    var format: String?
    var updatedAt: String?
    var ruleCount: Int?

    var isRemote: Bool {
        vehicleType?.caseInsensitiveCompare("Inline") != .orderedSame
    }

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case vehicleType
        case behavior
        case format
        case updatedAt
        case ruleCount
    }

    init(
        name: String,
        type: String? = nil,
        vehicleType: String? = nil,
        behavior: String? = nil,
        format: String? = nil,
        updatedAt: String? = nil,
        ruleCount: Int? = nil
    ) {
        self.name = name
        self.type = type
        self.vehicleType = vehicleType
        self.behavior = behavior
        self.format = format
        self.updatedAt = updatedAt
        self.ruleCount = ruleCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type)
        vehicleType = try container.decodeIfPresent(String.self, forKey: .vehicleType)
        behavior = try container.decodeIfPresent(String.self, forKey: .behavior)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        ruleCount = try container.decodeIfPresent(Int.self, forKey: .ruleCount)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(vehicleType, forKey: .vehicleType)
        try container.encodeIfPresent(behavior, forKey: .behavior)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(ruleCount, forKey: .ruleCount)
    }
}

struct ConnectionMetadata: Codable, Equatable, Sendable {
    var network: String?
    var type: String?
    var sourceIP: String?
    var destinationIP: String?
    var host: String?
    var process: String?
}

struct ConnectionInfo: Identifiable, Codable, Equatable, Sendable {
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

struct ConnectionsSnapshot: Codable, Equatable, Sendable {
    var uploadTotal: Int64?
    var downloadTotal: Int64?
    var connections: [ConnectionInfo]
}

struct ConnectionFilter: Equatable, Sendable {
    var sourceIP = ""
    var outbound = ""
    var minimumDownloadBytes: Int64 = 0

    func matches(_ connection: ConnectionInfo) -> Bool {
        let sourceMatches = sourceIP.isEmpty || (connection.metadata.sourceIP ?? "").localizedCaseInsensitiveContains(sourceIP)
        let outboundMatches = outbound.isEmpty || connection.outbound.localizedCaseInsensitiveContains(outbound)
        return sourceMatches && outboundMatches && connection.download >= minimumDownloadBytes
    }
}

struct LogEntry: Identifiable, Decodable, Equatable, Sendable {
    var id = UUID()
    var type: String
    var payload: String
    var date = Date()

    enum CodingKeys: String, CodingKey {
        case type
        case payload
    }
}

enum CoreUpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case release
    case alpha

    var id: String { rawValue }

    var title: String {
        switch self {
        case .release:
            return "Release"
        case .alpha:
            return "Alpha"
        }
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Array where Element == ProxyProvider {
    var visibleProxyProviders: [ProxyProvider] {
        filter { provider in
            provider.name != "default" && provider.vehicleType?.caseInsensitiveCompare("Compatible") != .orderedSame
        }
        .map { provider in
            var copy = provider
            copy.proxies = provider.proxies.filter { !$0.isGroup }
            return copy
        }
    }
}
