import Foundation

@MainActor
extension AppModel {
    func handleURLScheme(_ url: URL) async {
        do {
            try await handleURLRequest(AppURLRequest(url: url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleURLRequest(_ request: AppURLRequest) async throws {
        if let profileSelector = request.profileSelector {
            try selectProfile(matching: profileSelector)
        }

        switch request.command {
        case .navigate(let destination):
            navigate(to: destination)
        case .openLogBook(let level):
            if let level {
                logLevel = level
            }
            navigate(to: .logBook)
        case .editProfile(let selector):
            let profile = try profile(matching: selector)
            navigate(to: .editProfile(profile.id))
        case let .addProfile(profile, select):
            addProfileFromURL(profile, select: select)
        case let .updateProfile(update, select):
            try updateProfileFromURL(update, select: select)
        case .selectProfile(let selector):
            try selectProfile(matching: selector)
        case .deleteProfile(let selector):
            try deleteProfileFromURL(selector)
        case .refresh(let target):
            await refreshFromURL(target)
        case .setMode(let mode):
            await updateMode(mode)
        case let .selectProxy(group, proxy):
            await selectProxy(group: group, proxy: proxy)
        case .refreshProxyProvider(let name):
            try requireSelectedProfileKind(
                selectedProfile?.kind.showsProxyProviders == true,
                message: "Proxy provider refresh requires Mihomo profile.")
            await refreshProxyProvider(name)
        case .refreshRuleProvider(let name):
            await refreshRuleProvider(name)
        case .refreshProxyGroup(let name):
            try requireSelectedProfileKind(
                selectedProfile?.kind.supportsProxyGroupRefresh == true,
                message: "Proxy group refresh requires Surge profile.")
            _ = await refreshProxyGroup(name)
        case .testProxyGroupDelays:
            try requireSelectedProfileKind(
                selectedProfile?.kind.supportsProxyLatencyTesting == true,
                message: "Proxy latency test requires Mihomo or Singbox profile.")
            await testProxyGroupDelays()
        case let .setProxyGroupExpansion(group, expanded):
            setProxyGroupExpansionFromURL(group: group, expanded: expanded)
        case let .closeConnection(id):
            await closeConnection(id)
        case .closeAllConnections:
            await closeAllConnections()
        case let .setSourceIPTag(sourceIP, tag):
            if let tag {
                setSourceIPTag(tag, for: sourceIP)
            } else {
                removeSourceIPTag(for: sourceIP)
            }
        case .loadConfig:
            await loadConfig()
        case .reloadConfig:
            await reloadConfig()
        case .patchConfig(let patch):
            await patchConfigFromURL(patch)
        case .updateCore(let channel):
            _ = await upgradeCore(channel: channel)
        case .downloadSurgeMITMCertificate:
            try requireSelectedProfileKind(
                selectedProfile?.kind == .surge,
                message: "MITM certificate download requires Surge profile.")
            _ = await downloadSurgeMITMCertificate()
        case let .setSurgeFeature(feature, enabled):
            try requireSelectedProfileKind(
                selectedProfile?.kind == .surge,
                message: "Surge feature updates require Surge profile.")
            await patchConfigFromURL(.path(["features", feature.configKey], value: enabled ? "true" : "false"))
        }
    }

    private func navigate(to destination: AppNavigationDestination) {
        selectedTab = destination.targetTab
        navigationRequest = AppNavigationRequest(destination: destination)
    }

    private func addProfileFromURL(_ profile: APIProfile, select: Bool) {
        let previousProfileID = selectedProfileID
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
            if select {
                selectProfile(profile.id)
            }
        } else {
            addProfile(profile)
        }

        if !select, let previousProfileID, profiles.contains(where: { $0.id == previousProfileID }) {
            selectProfile(previousProfileID)
        }
    }

    private func updateProfileFromURL(_ update: AppURLProfileUpdate, select: Bool) throws {
        let current = try profile(matching: update.selector)
        let updated = APIProfile(
            id: current.id,
            name: update.name ?? current.name,
            kind: update.kind ?? current.kind,
            baseURL: update.baseURL ?? current.baseURL,
            secret: update.secret ?? current.secret
        )
        updateProfile(updated)
        if select {
            selectProfile(updated.id)
        }
    }

    @discardableResult
    private func selectProfile(matching selector: AppURLProfileSelector) throws -> APIProfile {
        let profile = try profile(matching: selector)
        selectProfile(profile.id)
        return profile
    }

    private func deleteProfileFromURL(_ selector: AppURLProfileSelector) throws {
        deleteProfile(try profile(matching: selector))
    }

    private func profile(matching selector: AppURLProfileSelector) throws -> APIProfile {
        switch selector {
        case .id(let id):
            guard let profile = profiles.first(where: { $0.id == id }) else {
                throw AppURLSchemeError.profileNotFound(id.uuidString)
            }
            return profile
        case .name(let name):
            guard let profile = profiles.first(where: {
                $0.name.localizedStandardCompare(name) == .orderedSame
            }) else {
                throw AppURLSchemeError.profileNotFound(name)
            }
            return profile
        }
    }

    private func refreshFromURL(_ target: AppURLRefreshTarget) async {
        switch target {
        case .all:
            await refreshAll()
        case .selected:
            await refreshSelectedTab()
        case .tab(let tab):
            selectedTab = tab
            switch tab {
            case .proxies:
                await refreshProxies()
            case .rule:
                await refreshRules()
            case .connections:
                await refreshConnections()
            case .more:
                await refreshAll()
            }
        }
    }

    private func setProxyGroupExpansionFromURL(group: String?, expanded: Bool) {
        guard let group else {
            setAllProxyGroupsExpanded(expanded, groups: proxyCollection.groups)
            return
        }
        setProxyGroupExpanded(expanded, groupName: group)
    }

    private func patchConfigFromURL(_ patch: AppURLConfigPatch) async {
        guard let client else { return }
        _ = await captureErrors {
            let currentConfigs = try await client.configs()
            let changedValues = configPatchValues(for: patch, currentConfigs: currentConfigs)
            guard !changedValues.isEmpty else { return }
            try await client.patchConfigs(changedValues)
            applyConfigs(try await client.configs())
            saveCachedDataIfUseful()
        }
    }

    private func configPatchValues(
        for patch: AppURLConfigPatch,
        currentConfigs: [String: JSONValue]
    ) -> [String: JSONValue] {
        switch patch {
        case .json(let values):
            return values
        case let .path(path, valueText):
            let value = configValue(for: path, valueText: valueText, currentConfigs: currentConfigs)
            var result: [String: JSONValue] = [:]
            result.mergeConfigPatch(path: path, value: value, originals: currentConfigs)
            return result
        }
    }

    private func configValue(
        for path: [String],
        valueText: String,
        currentConfigs: [String: JSONValue]
    ) -> JSONValue {
        let currentValue = currentConfigs.value(at: path)
        let field = BackendConfigCatalog.sections(for: selectedProfile?.kind, configs: currentConfigs)
            .flatMap(\.fields)
            .first { $0.path == path }

        if let field, let currentValue {
            return field.control.parsedValue(from: valueText, fallback: currentValue)
        }
        if let currentValue, currentValue.isScalar {
            return JSONScalarParser.parse(valueText, fallback: currentValue)
        }
        return JSONValue.parseJSON(valueText) ?? scalarURLValue(valueText)
    }

    private func scalarURLValue(_ text: String) -> JSONValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "true", "yes", "on":
            return .bool(true)
        case "false", "no", "off":
            return .bool(false)
        case "null":
            return .null
        default:
            return Double(trimmed).map(JSONValue.number) ?? .string(text)
        }
    }

    private func requireSelectedProfileKind(_ condition: Bool, message: String) throws {
        guard condition else {
            throw AppURLSchemeError.unsupportedFeature(message)
        }
    }
}
