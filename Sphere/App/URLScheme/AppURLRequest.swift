import Foundation

nonisolated struct AppURLRequest: Equatable, Sendable {
    var profileSelector: AppURLProfileSelector?
    var command: AppURLCommand

    nonisolated init(url: URL) throws {
        guard url.scheme?.lowercased() == "sphere" else {
            throw AppURLSchemeError.unsupportedScheme(url.scheme ?? "")
        }

        let query = AppURLQuery(url: url)
        let path = AppURLPath(url: url)
        profileSelector = AppURLProfileSelector.globalOverride(in: query)
        command = try Self.command(path: path, query: query)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func command(path: AppURLPath, query: AppURLQuery) throws -> AppURLCommand {
        guard let first = path.normalized.first else {
            if let tab = query.tabValue() {
                return .navigate(.tab(tab))
            }
            return .navigate(.tab(.proxies))
        }

        switch first {
        case "open", "go", "navigate":
            return try navigation(path: path, query: query, startIndex: 1)
        case "tab":
            guard let tab = query.tabValue() ?? AppTab(urlValue: path.rawSegment(at: 1)) else {
                throw AppURLSchemeError.invalidParameter("tab")
            }
            return .navigate(.tab(tab))
        case "profile", "profiles", "backend", "backends":
            return try profile(path: path, query: query)
        case "refresh":
            return .refresh(try refreshTarget(path: path, query: query, startIndex: 1))
        case "mode":
            return .setMode(try query.clashModeValue())
        case "proxy", "proxies":
            return try proxy(path: path, query: query)
        case "provider", "providers":
            return try provider(path: path, query: query)
        case "rule", "rules":
            return try rule(path: path, query: query)
        case "connection", "connections":
            return try connection(path: path, query: query)
        case "source-ip", "sourceip", "source":
            return try sourceIP(path: path, query: query)
        case "config", "configs", "configuration":
            return try config(path: path, query: query)
        case "core":
            return try core(path: path, query: query)
        case "update":
            if path.normalized.dropFirst().first == "core" {
                return .updateCore(query.coreUpdateChannelValue(default: .release))
            }
            return .updateCore(query.coreUpdateChannelValue(default: .release))
        case "surge":
            return try surge(path: path, query: query)
        case "log", "logs":
            return .openLogBook(query.logLevelValue())
        default:
            if let tab = AppTab(urlValue: first), path.count == 1 {
                return .navigate(.tab(tab))
            }
            throw AppURLSchemeError.unknownCommand(path.displayValue)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func navigation(
        path: AppURLPath,
        query: AppURLQuery,
        startIndex: Int
    ) throws -> AppURLCommand {
        if let tab = query.tabValue() {
            return .navigate(.tab(tab))
        }

        guard let value = path.normalizedSegment(at: startIndex) else {
            return .navigate(.tab(.proxies))
        }

        switch value {
        case "proxy", "proxies":
            return .navigate(.tab(.proxies))
        case "rule", "rules":
            return .navigate(.tab(.rule))
        case "connection", "connections":
            if query.bool("sheet", "list", "full") == true
                || path.normalizedSegment(at: startIndex + 1) == "list" {
                return .navigate(.connectionsList)
            }
            return .navigate(.tab(.connections))
        case "more", "settings":
            return .navigate(.tab(.more))
        case "config", "configs", "configuration":
            return .navigate(.configEditor)
        case "log", "logs", "log-book":
            return .openLogBook(query.logLevelValue())
        case "profile", "profiles", "backend", "backends":
            if path.normalizedSegment(at: startIndex + 1) == "add" {
                return .navigate(.addProfile)
            }
            if path.normalizedSegment(at: startIndex + 1) == "edit" {
                let selector = try profileSelector(
                    path: path, query: query, startIndex: startIndex + 2, nameIsSelector: true)
                return .editProfile(selector)
            }
            return .navigate(.tab(.more))
        default:
            guard let tab = AppTab(urlValue: value) else {
                throw AppURLSchemeError.unknownCommand(path.displayValue)
            }
            return .navigate(.tab(tab))
        }
    }

    private static func profile(path: AppURLPath, query: AppURLQuery) throws -> AppURLCommand {
        let action = path.normalizedSegment(at: 1) ?? "open"
        switch action {
        case "add", "create", "new":
            guard query.hasAny(ProfileField.directKeys) else {
                return .navigate(.addProfile)
            }
            let kind = query.backendKindValue(default: .mihomo)
            let profile = APIProfile(
                id: query.uuid("id") ?? UUID(),
                name: query.string("name", "title") ?? kind.title,
                kind: kind,
                baseURL: query.string("url", "baseurl", "base-url", "controller", "controller-url")
                    ?? kind.defaultBaseURL,
                secret: query.string("secret", "token", "key", "password") ?? ""
            )
            return .addProfile(profile, select: query.bool("select", "activate") ?? true)
        case "edit":
            let selector = try profileSelector(
                path: path, query: query, startIndex: 2, nameIsSelector: true)
            return .editProfile(selector)
        case "update", "set":
            let selector = try profileSelector(
                path: path, query: query, startIndex: 2, nameIsSelector: false)
            let update = AppURLProfileUpdate(
                selector: selector,
                name: query.string("name", "title"),
                kind: query.backendKindValue(),
                baseURL: query.string("url", "baseurl", "base-url", "controller", "controller-url"),
                secret: query.string("secret", "token", "key", "password")
            )
            return .updateProfile(update, select: query.bool("select", "activate") ?? false)
        case "select", "switch", "use":
            return .selectProfile(
                try profileSelector(path: path, query: query, startIndex: 2, nameIsSelector: true))
        case "delete", "remove":
            return .deleteProfile(
                try profileSelector(path: path, query: query, startIndex: 2, nameIsSelector: true))
        case "open", "list":
            return .navigate(.tab(.more))
        default:
            throw AppURLSchemeError.unknownCommand(path.displayValue)
        }
    }

    private static func proxy(path: AppURLPath, query: AppURLQuery) throws -> AppURLCommand {
        guard let action = path.normalizedSegment(at: 1) else {
            return .navigate(.tab(.proxies))
        }

        switch action {
        case "select", "set", "use":
            return .selectProxy(
                group: try query.requiredString("group", "group-name", "groupname"),
                proxy: try query.requiredString("proxy", "node", "name", "policy")
            )
        case "provider", "providers":
            guard path.normalized.contains("refresh") else {
                return .navigate(.tab(.proxies))
            }
            return .refreshProxyProvider(
                try query.string("name", "provider")
                    ?? trailingValue(path: path, startIndex: 2, excluding: ["refresh"]))
        case "group", "groups":
            if path.normalized.contains("refresh") {
                return .refreshProxyGroup(
                    try query.string("name", "group", "group-name")
                        ?? trailingValue(path: path, startIndex: 2, excluding: ["refresh"]))
            }
            if path.normalized.contains("expand") || path.normalized.contains("collapse") {
                let expanded =
                    query.bool("expanded", "open", "enabled")
                    ?? !path.normalized.contains("collapse")
                let group = query.string("name", "group", "group-name")
                    ?? (try? trailingValue(
                        path: path, startIndex: 2, excluding: ["expand", "collapse"]))
                return .setProxyGroupExpansion(
                    group: group,
                    expanded: expanded
                )
            }
            return .navigate(.tab(.proxies))
        case "latency", "delay", "speed", "speed-test", "test-latency":
            return .testProxyGroupDelays
        default:
            throw AppURLSchemeError.unknownCommand(path.displayValue)
        }
    }

    private static func provider(path: AppURLPath, query: AppURLQuery) throws -> AppURLCommand {
        let kind = path.normalizedSegment(at: 1) ?? query.string("type", "kind")?.urlNormalized
        guard path.normalized.contains("refresh") else {
            return .navigate(.tab(.proxies))
        }
        let name = try query.string("name", "provider")
            ?? trailingValue(path: path, startIndex: 1, excluding: ["proxy", "proxies", "rule", "rules", "refresh"])

        switch kind {
        case "rule", "rules":
            return .refreshRuleProvider(name)
        default:
            return .refreshProxyProvider(name)
        }
    }

    private static func rule(path: AppURLPath, query: AppURLQuery) throws -> AppURLCommand {
        guard let action = path.normalizedSegment(at: 1) else {
            return .navigate(.tab(.rule))
        }
        switch action {
        case "provider", "providers":
            guard path.normalized.contains("refresh") else {
                return .navigate(.tab(.rule))
            }
            return .refreshRuleProvider(
                try query.string("name", "provider")
                    ?? trailingValue(path: path, startIndex: 2, excluding: ["refresh"]))
        case "refresh":
            return .refresh(.tab(.rule))
        default:
            throw AppURLSchemeError.unknownCommand(path.displayValue)
        }
    }

    private static func connection(path: AppURLPath, query: AppURLQuery) throws -> AppURLCommand {
        guard let action = path.normalizedSegment(at: 1) else {
            return .navigate(.tab(.connections))
        }
        switch action {
        case "list", "show", "sheet":
            return .navigate(.connectionsList)
        case "close-all", "closeall", "kill-all":
            return .closeAllConnections
        case "close", "kill", "delete":
            if path.normalizedSegment(at: 2) == "all" {
                return .closeAllConnections
            }
            return .closeConnection(
                try query.string("id", "connection")
                    ?? trailingValue(path: path, startIndex: 2, excluding: ["all"]))
        case "refresh":
            return .refresh(.tab(.connections))
        default:
            throw AppURLSchemeError.unknownCommand(path.displayValue)
        }
    }

    private static func sourceIP(path: AppURLPath, query: AppURLQuery) throws -> AppURLCommand {
        guard path.normalized.contains("tag") else {
            throw AppURLSchemeError.unknownCommand(path.displayValue)
        }
        let sourceIP = try query.requiredString("ip", "source-ip", "sourceip", "source")
        let shouldClear = path.normalized.contains("clear") || path.normalized.contains("remove")
        let tag = shouldClear ? nil : try query.requiredString("tag", "name", "label")
        return .setSourceIPTag(sourceIP: sourceIP, tag: tag)
    }

    private static func config(path: AppURLPath, query: AppURLQuery) throws -> AppURLCommand {
        let action = path.normalizedSegment(at: 1) ?? "open"
        switch action {
        case "open", "show", "edit":
            return .navigate(.configEditor)
        case "load", "get":
            return .loadConfig
        case "reload":
            return .reloadConfig
        case "set", "patch", "update":
            if let jsonText = query.string("json", "patch"),
                let value = JSONValue.parseJSON(jsonText),
                case .object(let patch) = value {
                return .patchConfig(.json(patch))
            }
            let pathValue =
                query.string("path", "key")
                ?? path.rawSegments.dropFirst(2).joined(separator: ".")
            let configPath = pathValue.split(separator: ".").map(String.init)
            guard !configPath.isEmpty else {
                throw AppURLSchemeError.missingParameter("path")
            }
            return .patchConfig(
                .path(
                    configPath,
                    value: try query.requiredString("value", "to", "enabled", "set")
                ))
        default:
            throw AppURLSchemeError.unknownCommand(path.displayValue)
        }
    }

    private static func core(path: AppURLPath, query: AppURLQuery) throws -> AppURLCommand {
        guard path.normalizedSegment(at: 1) == "update" else {
            throw AppURLSchemeError.unknownCommand(path.displayValue)
        }
        return .updateCore(query.coreUpdateChannelValue(default: .release))
    }

    private static func surge(path: AppURLPath, query: AppURLQuery) throws -> AppURLCommand {
        let action = path.normalizedSegment(at: 1) ?? ""
        switch action {
        case "mitm", "certificate", "cert", "mitm-cert", "mitm-certificate":
            return .downloadSurgeMITMCertificate
        case "feature", "features":
            let feature = try query.surgeFeatureValue()
            let enabled = try query.requiredBool("enabled", "value", "on")
            return .setSurgeFeature(feature, enabled: enabled)
        default:
            throw AppURLSchemeError.unknownCommand(path.displayValue)
        }
    }

    private static func refreshTarget(
        path: AppURLPath,
        query: AppURLQuery,
        startIndex: Int
    ) throws -> AppURLRefreshTarget {
        let value =
            query.string("target", "scope", "tab")
            ?? path.rawSegment(at: startIndex)
            ?? "selected"
        switch value.urlNormalized {
        case "all":
            return .all
        case "selected", "current":
            return .selected
        case "proxy", "proxies":
            return .tab(.proxies)
        case "rule", "rules":
            return .tab(.rule)
        case "connection", "connections":
            return .tab(.connections)
        case "more", "overview":
            return .tab(.more)
        default:
            guard let tab = AppTab(urlValue: value) else {
                throw AppURLSchemeError.invalidParameter("target")
            }
            return .tab(tab)
        }
    }

    private static func profileSelector(
        path: AppURLPath,
        query: AppURLQuery,
        startIndex: Int,
        nameIsSelector: Bool
    ) throws -> AppURLProfileSelector {
        if let id = query.uuid("id", "profileid", "profile-id") {
            return .id(id)
        }
        if let value = query.string("profile", "target", "current", "current-name", "old-name") {
            return AppURLProfileSelector(value: value)
        }
        if nameIsSelector, let name = query.string("name", "profile-name") {
            return .name(name)
        }
        if let value = path.rawSegment(at: startIndex), !value.isEmpty {
            return AppURLProfileSelector(value: value)
        }
        throw AppURLSchemeError.missingParameter("profile")
    }

    private static func trailingValue(
        path: AppURLPath,
        startIndex: Int,
        excluding excludedValues: Set<String>
    ) throws -> String {
        for index in startIndex..<path.count {
            guard let normalized = path.normalizedSegment(at: index),
                !excludedValues.contains(normalized),
                let raw = path.rawSegment(at: index),
                !raw.isEmpty
            else {
                continue
            }
            return raw
        }
        throw AppURLSchemeError.missingParameter("name")
    }

    private static func requiredTab(_ value: String?) throws -> AppTab {
        guard let tab = AppTab(urlValue: value) else {
            throw AppURLSchemeError.invalidParameter("tab")
        }
        return tab
    }
}

nonisolated enum AppURLCommand: Equatable, Sendable {
    case navigate(AppNavigationDestination)
    case openLogBook(LogLevel?)
    case editProfile(AppURLProfileSelector)
    case addProfile(APIProfile, select: Bool)
    case updateProfile(AppURLProfileUpdate, select: Bool)
    case selectProfile(AppURLProfileSelector)
    case deleteProfile(AppURLProfileSelector)
    case refresh(AppURLRefreshTarget)
    case setMode(ClashMode)
    case selectProxy(group: String, proxy: String)
    case refreshProxyProvider(String)
    case refreshRuleProvider(String)
    case refreshProxyGroup(String)
    case testProxyGroupDelays
    case setProxyGroupExpansion(group: String?, expanded: Bool)
    case closeConnection(String)
    case closeAllConnections
    case setSourceIPTag(sourceIP: String, tag: String?)
    case loadConfig
    case reloadConfig
    case patchConfig(AppURLConfigPatch)
    case updateCore(CoreUpdateChannel)
    case downloadSurgeMITMCertificate
    case setSurgeFeature(SurgeFeature, enabled: Bool)
}

nonisolated enum AppURLRefreshTarget: Equatable, Sendable {
    case all
    case selected
    case tab(AppTab)
}

nonisolated enum AppURLConfigPatch: Equatable, Sendable {
    case path([String], value: String)
    case json([String: JSONValue])
}

nonisolated struct AppURLProfileUpdate: Equatable, Sendable {
    var selector: AppURLProfileSelector
    var name: String?
    var kind: BackendKind?
    var baseURL: String?
    var secret: String?
}

nonisolated enum AppURLProfileSelector: Equatable, Sendable {
    case id(UUID)
    case name(String)

    init(value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: trimmed) {
            self = .id(id)
        } else {
            self = .name(trimmed)
        }
    }

    static func globalOverride(in query: AppURLQuery) -> Self? {
        if let id = query.uuid("profileid", "profile-id") {
            return .id(id)
        }
        if let value = query.string("profile", "profile-name") {
            return Self(value: value)
        }
        return nil
    }
}

nonisolated enum AppURLSchemeError: LocalizedError, Equatable, Sendable {
    case unsupportedScheme(String)
    case unknownCommand(String)
    case missingParameter(String)
    case invalidParameter(String)
    case profileNotFound(String)
    case unsupportedFeature(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedScheme(let scheme):
            return "Unsupported URL scheme: \(scheme)"
        case .unknownCommand(let command):
            return "Unknown URL command: \(command)"
        case .missingParameter(let name):
            return "Missing URL parameter: \(name)"
        case .invalidParameter(let name):
            return "Invalid URL parameter: \(name)"
        case .profileNotFound(let value):
            return "Profile not found: \(value)"
        case .unsupportedFeature(let message):
            return message
        }
    }
}

private enum ProfileField {
    nonisolated static let directKeys = [
        "id", "name", "title", "kind", "type", "url", "baseurl", "base-url", "controller",
        "controller-url", "secret", "token", "key", "password",
    ]
}

private struct AppURLPath {
    var rawSegments: [String]
    var normalized: [String]

    nonisolated init(url: URL) {
        var segments: [String] = []
        if let host = url.host, !host.isEmpty {
            segments.append(host.removingPercentEncoding ?? host)
        }
        segments.append(
            contentsOf: url.pathComponents.compactMap { component in
                guard component != "/" else { return nil }
                return component.removingPercentEncoding ?? component
            })
        rawSegments = segments
        normalized = segments.map(\.urlNormalized)
    }

    nonisolated var count: Int { rawSegments.count }

    nonisolated var displayValue: String {
        rawSegments.joined(separator: "/")
    }

    nonisolated func rawSegment(at index: Int) -> String? {
        guard rawSegments.indices.contains(index) else { return nil }
        return rawSegments[index]
    }

    nonisolated func normalizedSegment(at index: Int) -> String? {
        guard normalized.indices.contains(index) else { return nil }
        return normalized[index]
    }
}

nonisolated struct AppURLQuery: Equatable, Sendable {
    private var values: [String: [String]]

    nonisolated init(url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        values = items.reduce(into: [:]) { result, item in
            let key = item.name.urlNormalized
            result[key, default: []].append(item.value ?? "")
        }
    }

    nonisolated func string(_ names: String...) -> String? {
        string(names)
    }

    nonisolated func string(_ names: [String]) -> String? {
        for name in names {
            guard let value = values[name.urlNormalized]?.last?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else {
                continue
            }
            return value
        }
        return nil
    }

    nonisolated func requiredString(_ names: String...) throws -> String {
        if let value = string(names) {
            return value
        }
        throw AppURLSchemeError.missingParameter(names.first ?? "value")
    }

    nonisolated func bool(_ names: String...) -> Bool? {
        bool(names)
    }

    nonisolated func bool(_ names: [String]) -> Bool? {
        guard let value = string(names)?.urlNormalized else { return nil }
        if ["1", "true", "yes", "on", "enable", "enabled"].contains(value) {
            return true
        }
        if ["0", "false", "no", "off", "disable", "disabled"].contains(value) {
            return false
        }
        return nil
    }

    nonisolated func requiredBool(_ names: String...) throws -> Bool {
        if let value = bool(names) {
            return value
        }
        throw AppURLSchemeError.invalidParameter(names.first ?? "value")
    }

    nonisolated func uuid(_ names: String...) -> UUID? {
        guard let value = string(names) else { return nil }
        return UUID(uuidString: value)
    }

    nonisolated func hasAny(_ names: [String]) -> Bool {
        names.contains { values[$0.urlNormalized] != nil }
    }

    nonisolated func tabValue() -> AppTab? {
        AppTab(urlValue: string("tab", "target", "scope"))
    }

    nonisolated func clashModeValue() throws -> ClashMode {
        guard let mode = string("value", "mode", "name"),
            let result = ClashMode(mihomoValue: mode) else {
            throw AppURLSchemeError.invalidParameter("mode")
        }
        return result
    }

    nonisolated func backendKindValue() -> BackendKind? {
        guard let value = string("kind", "type", "backend") else { return nil }
        switch value.urlNormalized {
        case "mihomo", "clash", "clash-meta", "meta":
            return .mihomo
        case "singbox", "sing-box":
            return .singbox
        case "surge":
            return .surge
        default:
            return nil
        }
    }

    nonisolated func backendKindValue(default defaultValue: BackendKind) -> BackendKind {
        backendKindValue() ?? defaultValue
    }

    nonisolated func logLevelValue() -> LogLevel? {
        guard let value = string("level", "value")?.urlNormalized else { return nil }
        return LogLevel(rawValue: value)
    }

    nonisolated func coreUpdateChannelValue(default defaultValue: CoreUpdateChannel)
        -> CoreUpdateChannel {
        guard let value = string("channel", "value")?.urlNormalized,
            let channel = CoreUpdateChannel(rawValue: value) else {
            return defaultValue
        }
        return channel
    }

    nonisolated func surgeFeatureValue() throws -> SurgeFeature {
        guard let value = string("name", "feature", "key") else {
            throw AppURLSchemeError.missingParameter("feature")
        }
        let normalized = value.urlNormalized.replacing("-", with: "_")
        guard let feature = SurgeFeature(rawValue: normalized) else {
            throw AppURLSchemeError.invalidParameter("feature")
        }
        return feature
    }
}

extension AppTab {
    nonisolated init?(urlValue value: String?) {
        switch value?.urlNormalized {
        case "proxy", "proxies":
            self = .proxies
        case "rule", "rules":
            self = .rule
        case "connection", "connections":
            self = .connections
        case "more", "settings", "overview":
            self = .more
        default:
            return nil
        }
    }
}

private extension String {
    nonisolated var urlNormalized: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacing("_", with: "-")
    }
}
