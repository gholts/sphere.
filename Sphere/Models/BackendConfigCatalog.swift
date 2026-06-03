import Foundation

nonisolated struct BackendConfigSection: Identifiable, Equatable, Sendable {
    var id: String { title }
    var title: String
    var fields: [BackendConfigField]
}

nonisolated struct BackendConfigField: Identifiable, Equatable, Sendable {
    var id: String { path.joined(separator: ".") }
    var section: String
    var title: String
    var path: [String]
    var control: BackendConfigControl

    init(section: String, title: String, path: String, control: BackendConfigControl) {
        self.section = section
        self.title = title
        self.path = path.split(separator: ".").map(String.init)
        self.control = control
    }
}

nonisolated enum BackendConfigControl: Equatable, Sendable {
    case toggle
    case number
    case text
    case longText
    case picker([String])
    case stringList
    case numberList
    case json

    func displayText(for value: JSONValue) -> String {
        switch self {
        case .stringList, .numberList:
            return value.stringListText.joined(separator: "\n")
        case .json:
            return value.prettyJSONText
        default:
            return value.displayText
        }
    }

    func parsedValue(from text: String, fallback: JSONValue) -> JSONValue {
        switch self {
        case .toggle:
            return .bool(
                ["true", "1", "yes", "on"].contains(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()))
        case .number:
            return .number(Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
        case .text, .longText, .picker:
            return .string(text)
        case .stringList:
            let values =
                text
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if values.isEmpty, fallback == .null {
                return .null
            }
            return .array(values.map(JSONValue.string))
        case .numberList:
            let values =
                text
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .compactMap(Double.init)
            if values.isEmpty, fallback == .null {
                return .null
            }
            return .array(values.map(JSONValue.number))
        case .json:
            return JSONValue.parseJSON(text) ?? fallback
        }
    }

    func pickerOptions(containing value: String) -> [String] {
        guard case .picker(let options) = self else { return [] }
        guard !value.isEmpty, !options.contains(value) else { return options }
        return [value] + options
    }
}

nonisolated enum BackendConfigCatalog {
    static func sections(for kind: BackendKind?, configs: [String: JSONValue])
        -> [BackendConfigSection] {
        let knownFields = fields(for: kind)
        let visibleKnownFields = knownFields.filter { configs.value(at: $0.path) != nil }
        let order = sectionOrder(for: kind)

        return order.compactMap { title in
            let sectionFields = visibleKnownFields.filter { $0.section == title }
            guard !sectionFields.isEmpty else { return nil }
            return BackendConfigSection(title: title, fields: sectionFields)
        }
    }

    static func fields(for kind: BackendKind?) -> [BackendConfigField] {
        switch kind {
        case .mihomo:
            return mihomoFields
        case .singbox:
            return singboxFields
        case .none:
            return []
        }
    }

    private static func sectionOrder(for kind: BackendKind?) -> [String] {
        switch kind {
        case .mihomo:
            return [
                "Ports",
                "Access",
                "Runtime",
                "API",
                "Interface",
                "DNS",
                "Sniffer",
                "TUN",
                "Geo",
                "Transport",
                "Inbound",
                "TLS",
                "Experimental",
                "NTP",
                "Tunnels",
            ]
        case .singbox:
            return ["Clash API", "Runtime", "Access"]
        case .none:
            return []
        }
    }

    private static let mihomoFields: [BackendConfigField] = [
        BackendConfigField(
            section: "Ports", title: "Mixed Port", path: "mixed-port", control: .number),
        BackendConfigField(section: "Ports", title: "HTTP Port", path: "port", control: .number),
        BackendConfigField(
            section: "Ports", title: "SOCKS Port", path: "socks-port", control: .number),
        BackendConfigField(
            section: "Ports", title: "Redir Port", path: "redir-port", control: .number),
        BackendConfigField(
            section: "Ports", title: "TProxy Port", path: "tproxy-port", control: .number),

        BackendConfigField(
            section: "Access", title: "Allow LAN", path: "allow-lan", control: .toggle),
        BackendConfigField(
            section: "Access", title: "Bind Address", path: "bind-address", control: .text),
        BackendConfigField(
            section: "Access", title: "LAN Allowed IPs", path: "lan-allowed-ips",
            control: .stringList),
        BackendConfigField(
            section: "Access", title: "LAN Blocked IPs", path: "lan-disallowed-ips",
            control: .stringList),
        BackendConfigField(
            section: "Access", title: "Authentication", path: "authentication", control: .stringList
        ),
        BackendConfigField(
            section: "Access", title: "Skip Auth Prefixes", path: "skip-auth-prefixes",
            control: .stringList),

        BackendConfigField(
            section: "Runtime", title: "Mode", path: "mode",
            control: .picker(["rule", "global", "direct"])),
        BackendConfigField(
            section: "Runtime", title: "Log Level", path: "log-level",
            control: .picker(["debug", "info", "warning", "error", "silent"])),
        BackendConfigField(section: "Runtime", title: "IPv6", path: "ipv6", control: .toggle),
        BackendConfigField(
            section: "Runtime", title: "Unified Delay", path: "unified-delay", control: .toggle),
        BackendConfigField(
            section: "Runtime", title: "TCP Concurrent", path: "tcp-concurrent", control: .toggle),
        BackendConfigField(
            section: "Runtime", title: "Find Process", path: "find-process-mode",
            control: .picker(["off", "strict", "always"])),
        BackendConfigField(
            section: "Runtime", title: "Sniffing", path: "sniffing", control: .toggle),
        BackendConfigField(
            section: "Runtime", title: "Client Fingerprint", path: "global-client-fingerprint",
            control: .text),
        BackendConfigField(
            section: "Runtime", title: "User Agent", path: "global-ua", control: .text),
        BackendConfigField(
            section: "Runtime", title: "Disable Keep Alive", path: "disable-keep-alive",
            control: .toggle),
        BackendConfigField(
            section: "Runtime", title: "Keep Alive Idle", path: "keep-alive-idle", control: .number),
        BackendConfigField(
            section: "Runtime", title: "Keep Alive Interval", path: "keep-alive-interval",
            control: .number),
        BackendConfigField(
            section: "Runtime", title: "ETag Support", path: "etag-support", control: .toggle),

        BackendConfigField(
            section: "API", title: "External Controller", path: "external-controller",
            control: .text),
        BackendConfigField(
            section: "API", title: "Controller CORS Origins",
            path: "external-controller-cors.allow-origins", control: .stringList),
        BackendConfigField(
            section: "API", title: "Controller Private Network",
            path: "external-controller-cors.allow-private-network", control: .toggle),
        BackendConfigField(
            section: "API", title: "Controller Unix Socket", path: "external-controller-unix",
            control: .text),
        BackendConfigField(
            section: "API", title: "Controller Named Pipe", path: "external-controller-pipe",
            control: .text),
        BackendConfigField(
            section: "API", title: "Controller TLS", path: "external-controller-tls", control: .text
        ),
        BackendConfigField(section: "API", title: "Secret", path: "secret", control: .text),
        BackendConfigField(
            section: "API", title: "External UI", path: "external-ui", control: .text),
        BackendConfigField(
            section: "API", title: "External UI Name", path: "external-ui-name", control: .text),
        BackendConfigField(
            section: "API", title: "External UI URL", path: "external-ui-url", control: .text),

        BackendConfigField(
            section: "Interface", title: "Interface", path: "interface-name", control: .text),
        BackendConfigField(
            section: "Interface", title: "Routing Mark", path: "routing-mark", control: .number),
        BackendConfigField(
            section: "Interface", title: "Store Selected", path: "profile.store-selected",
            control: .toggle),
        BackendConfigField(
            section: "Interface", title: "Store Fake IP", path: "profile.store-fake-ip",
            control: .toggle),

        BackendConfigField(section: "DNS", title: "Enable", path: "dns.enable", control: .toggle),
        BackendConfigField(section: "DNS", title: "Listen", path: "dns.listen", control: .text),
        BackendConfigField(section: "DNS", title: "IPv6", path: "dns.ipv6", control: .toggle),
        BackendConfigField(
            section: "DNS", title: "Cache Algorithm", path: "dns.cache-algorithm",
            control: .picker(["lru", "arc"])),
        BackendConfigField(
            section: "DNS", title: "Prefer HTTP/3", path: "dns.prefer-h3", control: .toggle),
        BackendConfigField(
            section: "DNS", title: "Use Hosts", path: "dns.use-hosts", control: .toggle),
        BackendConfigField(
            section: "DNS", title: "Use System Hosts", path: "dns.use-system-hosts",
            control: .toggle),
        BackendConfigField(
            section: "DNS", title: "Respect Rules", path: "dns.respect-rules", control: .toggle),
        BackendConfigField(
            section: "DNS", title: "Default Nameserver", path: "dns.default-nameserver",
            control: .stringList),
        BackendConfigField(
            section: "DNS", title: "Enhanced Mode", path: "dns.enhanced-mode",
            control: .picker(["redir-host", "fake-ip"])),
        BackendConfigField(
            section: "DNS", title: "Fake IP Range", path: "dns.fake-ip-range", control: .text),
        BackendConfigField(
            section: "DNS", title: "Fake IP Range IPv6", path: "dns.fake-ip-range6", control: .text),
        BackendConfigField(
            section: "DNS", title: "Fake IP Filter Mode", path: "dns.fake-ip-filter-mode",
            control: .picker(["blacklist", "whitelist", "rule"])),
        BackendConfigField(
            section: "DNS", title: "Fake IP Filter", path: "dns.fake-ip-filter",
            control: .stringList),
        BackendConfigField(
            section: "DNS", title: "Fake IP TTL", path: "dns.fake-ip-ttl", control: .number),
        BackendConfigField(
            section: "DNS", title: "Nameserver", path: "dns.nameserver", control: .stringList),
        BackendConfigField(
            section: "DNS", title: "Nameserver Policy", path: "dns.nameserver-policy",
            control: .json),
        BackendConfigField(
            section: "DNS", title: "Proxy Nameserver", path: "dns.proxy-server-nameserver",
            control: .stringList),
        BackendConfigField(
            section: "DNS", title: "Proxy Nameserver Policy",
            path: "dns.proxy-server-nameserver-policy",
            control: .json),
        BackendConfigField(
            section: "DNS", title: "Direct Nameserver", path: "dns.direct-nameserver",
            control: .stringList),
        BackendConfigField(
            section: "DNS", title: "Direct Nameserver Follow Policy",
            path: "dns.direct-nameserver-follow-policy", control: .toggle),
        BackendConfigField(
            section: "DNS", title: "Fallback", path: "dns.fallback", control: .stringList),
        BackendConfigField(
            section: "DNS", title: "Fallback GEOIP", path: "dns.fallback-filter.geoip",
            control: .toggle),
        BackendConfigField(
            section: "DNS", title: "Fallback GEOIP Code", path: "dns.fallback-filter.geoip-code",
            control: .text),
        BackendConfigField(
            section: "DNS", title: "Fallback Geosite", path: "dns.fallback-filter.geosite",
            control: .stringList),
        BackendConfigField(
            section: "DNS", title: "Fallback IP CIDR", path: "dns.fallback-filter.ipcidr",
            control: .stringList),
        BackendConfigField(
            section: "DNS", title: "Fallback Domain", path: "dns.fallback-filter.domain",
            control: .stringList),
        BackendConfigField(section: "DNS", title: "Hosts", path: "hosts", control: .json),

        BackendConfigField(
            section: "Sniffer", title: "Enable", path: "sniffer.enable", control: .toggle),
        BackendConfigField(
            section: "Sniffer", title: "Force DNS Mapping", path: "sniffer.force-dns-mapping",
            control: .toggle),
        BackendConfigField(
            section: "Sniffer", title: "Parse Pure IP", path: "sniffer.parse-pure-ip",
            control: .toggle),
        BackendConfigField(
            section: "Sniffer", title: "Override Destination", path: "sniffer.override-destination",
            control: .toggle),
        BackendConfigField(
            section: "Sniffer", title: "Protocol Rules", path: "sniffer.sniff", control: .json),
        BackendConfigField(
            section: "Sniffer", title: "Force Domain", path: "sniffer.force-domain",
            control: .stringList),
        BackendConfigField(
            section: "Sniffer", title: "Skip Domain", path: "sniffer.skip-domain",
            control: .stringList),
        BackendConfigField(
            section: "Sniffer", title: "Skip Source Address", path: "sniffer.skip-src-address",
            control: .stringList),
        BackendConfigField(
            section: "Sniffer", title: "Skip Destination Address", path: "sniffer.skip-dst-address",
            control: .stringList),

        BackendConfigField(section: "TUN", title: "Enable", path: "tun.enable", control: .toggle),
        BackendConfigField(section: "TUN", title: "Device", path: "tun.device", control: .text),
        BackendConfigField(
            section: "TUN", title: "Stack", path: "tun.stack",
            control: .picker(["system", "gvisor", "mixed"])),
        BackendConfigField(
            section: "TUN", title: "DNS Hijack", path: "tun.dns-hijack", control: .stringList),
        BackendConfigField(
            section: "TUN", title: "IPv4 Address", path: "tun.inet4-address", control: .stringList),
        BackendConfigField(
            section: "TUN", title: "IPv6 Address", path: "tun.inet6-address", control: .stringList),
        BackendConfigField(
            section: "TUN", title: "Auto Route", path: "tun.auto-route", control: .toggle),
        BackendConfigField(
            section: "TUN", title: "Auto Detect Interface", path: "tun.auto-detect-interface",
            control: .toggle),
        BackendConfigField(
            section: "TUN", title: "Auto Redirect", path: "tun.auto-redirect", control: .toggle),
        BackendConfigField(
            section: "TUN", title: "Strict Route", path: "tun.strict-route", control: .toggle),
        BackendConfigField(section: "TUN", title: "MTU", path: "tun.mtu", control: .number),
        BackendConfigField(section: "TUN", title: "GSO", path: "tun.gso", control: .toggle),
        BackendConfigField(
            section: "TUN", title: "GSO Max Size", path: "tun.gso-max-size", control: .number),
        BackendConfigField(
            section: "TUN", title: "File Descriptor", path: "tun.file-descriptor", control: .number),
        BackendConfigField(
            section: "TUN", title: "Recvmsgx", path: "tun.recvmsgx", control: .toggle),
        BackendConfigField(
            section: "TUN", title: "UDP Timeout", path: "tun.udp-timeout", control: .number),
        BackendConfigField(
            section: "TUN", title: "IPRoute2 Table Index", path: "tun.iproute2-table-index",
            control: .number),
        BackendConfigField(
            section: "TUN", title: "IPRoute2 Rule Index", path: "tun.iproute2-rule-index",
            control: .number),
        BackendConfigField(
            section: "TUN", title: "Endpoint Independent NAT", path: "tun.endpoint-independent-nat",
            control: .toggle),
        BackendConfigField(
            section: "TUN", title: "Route Address Set", path: "tun.route-address-set",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "Route Exclude Address Set",
            path: "tun.route-exclude-address-set",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "Route Address", path: "tun.route-address", control: .stringList),
        BackendConfigField(
            section: "TUN", title: "Route Exclude Address", path: "tun.route-exclude-address",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "Include Interface", path: "tun.include-interface",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "Exclude Interface", path: "tun.exclude-interface",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "Include UID", path: "tun.include-uid", control: .numberList),
        BackendConfigField(
            section: "TUN", title: "Include UID Range", path: "tun.include-uid-range",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "Exclude UID", path: "tun.exclude-uid", control: .numberList),
        BackendConfigField(
            section: "TUN", title: "Exclude UID Range", path: "tun.exclude-uid-range",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "Include Android User", path: "tun.include-android-user",
            control: .numberList),
        BackendConfigField(
            section: "TUN", title: "Include Package", path: "tun.include-package",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "Exclude Package", path: "tun.exclude-package",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "IPv4 Route Address", path: "tun.inet4-route-address",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "IPv6 Route Address", path: "tun.inet6-route-address",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "IPv4 Route Exclude", path: "tun.inet4-route-exclude-address",
            control: .stringList),
        BackendConfigField(
            section: "TUN", title: "IPv6 Route Exclude", path: "tun.inet6-route-exclude-address",
            control: .stringList),

        BackendConfigField(
            section: "Geo", title: "Auto Update", path: "geo-auto-update", control: .toggle),
        BackendConfigField(
            section: "Geo", title: "Update Interval", path: "geo-update-interval", control: .number),
        BackendConfigField(
            section: "Geo", title: "Geodata Mode", path: "geodata-mode", control: .toggle),
        BackendConfigField(
            section: "Geo", title: "Geodata Loader", path: "geodata-loader",
            control: .picker(["standard", "memconservative"])),
        BackendConfigField(
            section: "Geo", title: "Geosite Matcher", path: "geosite-matcher",
            control: .picker(["mph", "succinct"])),
        BackendConfigField(
            section: "Geo", title: "GEO IP URL", path: "geox-url.geo-ip", control: .text),
        BackendConfigField(
            section: "Geo", title: "GEO Site URL", path: "geox-url.geo-site", control: .text),
        BackendConfigField(
            section: "Geo", title: "GEO IP URL", path: "geox-url.geoip", control: .text),
        BackendConfigField(
            section: "Geo", title: "GEO Site URL", path: "geox-url.geosite", control: .text),
        BackendConfigField(
            section: "Geo", title: "MMDB URL", path: "geox-url.mmdb", control: .text),
        BackendConfigField(section: "Geo", title: "ASN URL", path: "geox-url.asn", control: .text),

        BackendConfigField(
            section: "Transport", title: "Inbound TFO", path: "inbound-tfo", control: .toggle),
        BackendConfigField(
            section: "Transport", title: "Inbound MPTCP", path: "inbound-mptcp", control: .toggle),

        BackendConfigField(
            section: "Inbound", title: "Listeners", path: "listeners", control: .json),
        BackendConfigField(
            section: "Inbound", title: "TUIC Server", path: "tuic-server", control: .json),

        BackendConfigField(
            section: "TLS", title: "Certificate", path: "tls.certificate", control: .longText),
        BackendConfigField(
            section: "TLS", title: "Private Key", path: "tls.private-key", control: .longText),
        BackendConfigField(
            section: "TLS", title: "ECH Key", path: "tls.ech-key", control: .longText),

        BackendConfigField(
            section: "Experimental", title: "Disable QUIC GSO",
            path: "experimental.quic-go-disable-gso",
            control: .toggle),
        BackendConfigField(
            section: "Experimental", title: "Disable QUIC ECN",
            path: "experimental.quic-go-disable-ecn",
            control: .toggle),
        BackendConfigField(
            section: "Experimental", title: "Dialer IP4P Convert",
            path: "experimental.dialer-ip4p-convert", control: .toggle),

        BackendConfigField(section: "NTP", title: "Enable", path: "ntp.enable", control: .toggle),
        BackendConfigField(
            section: "NTP", title: "Write To System", path: "ntp.write-to-system", control: .toggle),
        BackendConfigField(section: "NTP", title: "Server", path: "ntp.server", control: .text),
        BackendConfigField(section: "NTP", title: "Port", path: "ntp.port", control: .number),
        BackendConfigField(
            section: "NTP", title: "Interval", path: "ntp.interval", control: .number),

        BackendConfigField(section: "Tunnels", title: "Tunnels", path: "tunnels", control: .json),
    ]

    private static let singboxFields: [BackendConfigField] = [
        BackendConfigField(
            section: "Clash API", title: "External Controller", path: "external_controller",
            control: .text),
        BackendConfigField(
            section: "Clash API", title: "External UI", path: "external_ui", control: .text),
        BackendConfigField(
            section: "Clash API", title: "UI Download URL", path: "external_ui_download_url",
            control: .text),
        BackendConfigField(
            section: "Clash API", title: "UI Download Detour", path: "external_ui_download_detour",
            control: .text),
        BackendConfigField(section: "Clash API", title: "Secret", path: "secret", control: .text),

        BackendConfigField(
            section: "Runtime", title: "Mode", path: "mode",
            control: .picker(["Rule", "Global", "Direct"])),
        BackendConfigField(
            section: "Runtime", title: "Default Mode", path: "default_mode",
            control: .picker(["Rule", "Global", "Direct"])),

        BackendConfigField(
            section: "Access", title: "Allowed Origins", path: "access_control_allow_origin",
            control: .stringList),
        BackendConfigField(
            section: "Access", title: "Allow Private Network",
            path: "access_control_allow_private_network", control: .toggle),
    ]
}

extension JSONValue {
    nonisolated func value(at path: ArraySlice<String>) -> JSONValue? {
        guard let key = path.first else { return self }
        guard case .object(let values) = self else { return nil }
        return values[key]?.value(at: path.dropFirst())
    }

    nonisolated var stringListText: [String] {
        switch self {
        case .array(let values):
            return values.map(\.displayText)
        case .string(let value):
            return value.isEmpty ? [] : [value]
        case .null:
            return []
        default:
            return [displayText]
        }
    }

    nonisolated var prettyJSONText: String {
        guard let data = try? JSONEncoder().encode(self),
            let object = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: prettyData, encoding: .utf8)
        else {
            return displayText
        }
        return text
    }

    nonisolated static func parseJSON(_ text: String) -> JSONValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    nonisolated func value(at path: [String]) -> JSONValue? {
        guard let key = path.first else { return nil }
        guard let value = self[key] else { return nil }
        return value.value(at: path.dropFirst())
    }

    nonisolated mutating func mergeJSONPatch(_ patch: [String: JSONValue]) {
        for (key, value) in patch {
            if case .object(let current)? = self[key],
                case .object(let incoming) = value {
                var merged = current
                merged.mergeJSONPatch(incoming)
                self[key] = .object(merged)
            } else {
                self[key] = value
            }
        }
    }

    nonisolated mutating func mergeConfigPatch(
        path: [String], value: JSONValue, originals: [String: JSONValue]
    ) {
        guard let rootKey = path.first else { return }
        guard path.count > 1 else {
            self[rootKey] = value
            return
        }

        var rootValues: [String: JSONValue]
        if case .object(let pending)? = self[rootKey] {
            rootValues = pending
        } else if case .object(let original)? = originals[rootKey] {
            rootValues = original
        } else {
            mergeJSONPatch(Self.jsonPatch(path: path, value: value))
            return
        }

        rootValues.mergeJSONPatch(Self.jsonPatch(path: Array(path.dropFirst()), value: value))
        self[rootKey] = .object(rootValues)
    }

    nonisolated static func jsonPatch(path: [String], value: JSONValue) -> [String: JSONValue] {
        guard let key = path.first else { return [:] }
        guard path.count > 1 else { return [key: value] }
        return [key: .object(jsonPatch(path: Array(path.dropFirst()), value: value))]
    }
}
