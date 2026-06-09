import Foundation

nonisolated struct ProxyItem: Identifiable, Equatable, Codable, Sendable {
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

nonisolated struct DelayHistory: Codable, Equatable, Sendable {
    var time: String?
    var delay: Int?
}

nonisolated struct ProxyGroupRefreshReport: Equatable, Sendable {
    var groupName: String
    var message: String
}

nonisolated struct ProxyCollection: Codable, Equatable, Sendable {
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

    func applyingDelayResults(_ delays: [String: Int]) -> Self {
        guard !delays.isEmpty else { return self }
        return Self(
            proxies: proxies.map { $0.applyingDelayResult(delays[$0.name]) },
            groups: groups.map { $0.applyingDelayResult(delays[$0.name]) }
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let cachedGroups = try container.decodeIfPresent([ProxyItem].self, forKey: .groups) {
            proxies = try container.decodeIfPresent([ProxyItem].self, forKey: .proxies) ?? []
            groups = cachedGroups
            return
        }

        let values = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .proxies)
        let orderedProxies = try values.allKeys.map {
            try values.decode(ProxyItem.self, forKey: $0)
        }
        proxies = orderedProxies.filter { !$0.isGroup }

        let groupCandidates = orderedProxies.filter(\.isGroup)
        if let global = orderedProxies.first(where: { $0.name == "GLOBAL" }), !global.all.isEmpty {
            let sourceOrder = Dictionary(
                uniqueKeysWithValues: groupCandidates.enumerated().map {
                    ($0.element.name, $0.offset)
                })
            let globalOrder = Dictionary(
                uniqueKeysWithValues: global.all.enumerated().map { ($0.element, $0.offset) })
            groups = groupCandidates.sorted { left, right in
                if left.name == "GLOBAL" { return true }
                if right.name == "GLOBAL" { return false }
                switch (globalOrder[left.name], globalOrder[right.name]) {
                case let (.some(leftIndex), .some(rightIndex)):
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

fileprivate extension ProxyItem {
    nonisolated func applyingDelayResult(_ delay: Int?) -> ProxyItem {
        guard let delay else { return self }
        var copy = self
        copy.delay = delay
        return copy
    }
}

nonisolated struct ProxyProvider: Identifiable, Codable, Equatable, Sendable {
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
        totalBytes =
            try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? info?.totalBytes
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

nonisolated struct ProviderCollection<T: Decodable & Identifiable & Equatable>: Decodable, Equatable {
    var providers: [T]

    enum CodingKeys: String, CodingKey {
        case providers
    }

    init(providers: [T] = []) {
        self.providers = providers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let values = try? container.nestedContainer(
            keyedBy: DynamicCodingKey.self, forKey: .providers) {
            providers = try values.allKeys.map { try values.decode(T.self, forKey: $0) }
        } else {
            providers = try container.decodeIfPresent([T].self, forKey: .providers) ?? []
        }
    }
}

nonisolated struct SubscriptionInfo: Codable, Equatable, Sendable {
    var upload: Int64?
    var download: Int64?
    var total: Int64?
    var expire: Int64?

    var usedBytes: Int64? {
        switch (upload, download) {
        case let (.some(upload), .some(download)):
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
        upload =
            try container.decodeIfPresent(Int64.self, forKey: .upload)
            ?? container.decodeIfPresent(Int64.self, forKey: .upperUpload)
        download =
            try container.decodeIfPresent(Int64.self, forKey: .download)
            ?? container.decodeIfPresent(Int64.self, forKey: .upperDownload)
        total =
            try container.decodeIfPresent(Int64.self, forKey: .total)
            ?? container.decodeIfPresent(Int64.self, forKey: .upperTotal)
        expire =
            try container.decodeIfPresent(Int64.self, forKey: .expire)
            ?? container.decodeIfPresent(Int64.self, forKey: .upperExpire)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(upload, forKey: .upload)
        try container.encodeIfPresent(download, forKey: .download)
        try container.encodeIfPresent(total, forKey: .total)
        try container.encodeIfPresent(expire, forKey: .expire)
    }
}

extension Array where Element == ProxyProvider {
    nonisolated var visibleProxyProviders: [ProxyProvider] {
        filter { provider in
            provider.name != "default"
                && provider.vehicleType?.caseInsensitiveCompare("Compatible") != .orderedSame
        }
        .map { provider in
            var copy = provider
            copy.proxies = provider.proxies.filter { !$0.isGroup }
            return copy
        }
    }
}
