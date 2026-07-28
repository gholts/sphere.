import Foundation

extension SurgeClient {
    func configs() async throws -> [String: JSONValue] {
        async let globalResult = Self.result { try await globalPolicy() }
        async let modulesResult = Self.result { try await modules() }
        async let featureValues = configuredFeatureValues()

        var values: [String: JSONValue] = [:]
        let outbound = try await outbound()
        values.mergeJSONPatch(["outbound": .object(["mode": .string(outbound.mode)])])

        if case .success(let global) = await globalResult, !global.policy.isEmpty {
            values.mergeJSONPatch([
                "outbound": .object(["global_policy": .string(global.policy)]),
            ])
        }

        let features = await featureValues
        if !features.isEmpty {
            values["features"] = .object(features)
        }

        if case .success(let modules) = await modulesResult {
            let enabled = Set(modules.enabled)
            let moduleValues = Dictionary(
                uniqueKeysWithValues: modules.available.map {
                    ($0, JSONValue.bool(enabled.contains($0)))
                }
            )
            if !moduleValues.isEmpty {
                values["modules"] = .object(moduleValues)
            }
        }

        try Task.checkCancellation()
        return values
    }

    func patchConfigs(_ values: [String: JSONValue]) async throws {
        var didPatch = false

        if case .object(let outbound)? = values["outbound"] {
            if case .string(let mode)? = outbound["mode"] {
                try await updateOutboundMode(mode)
                didPatch = true
            }
            if case .string(let policy)? = outbound["global_policy"] {
                try await updateGlobalPolicy(policy)
                didPatch = true
            }
        }

        if case .object(let features)? = values["features"] {
            for feature in SurgeFeature.allCases {
                if case .bool(let enabled)? = features[feature.configKey] {
                    try await updateFeature(feature, enabled: enabled)
                    didPatch = true
                }
            }
        }

        if case .object(let modules)? = values["modules"] {
            let toggles = modules.compactMapValues { value -> Bool? in
                if case .bool(let enabled) = value {
                    return enabled
                }
                return nil
            }
            if !toggles.isEmpty {
                try await api.post(.modules, body: toggles)
                didPatch = true
            }
        }

        guard didPatch else {
            throw BackendError.unsupportedBackend("Surge config patch")
        }
    }

    func reloadConfig() async throws {
        try await api.post(.profilesReload)
    }

    func clashMode() async throws -> ClashMode {
        try await outbound().clashMode
    }

    func updateClashMode(_ mode: ClashMode) async throws {
        let surgeMode = switch mode {
        case .direct:
            "direct"
        case .global:
            "proxy"
        case .rule:
            "rule"
        }
        try await updateOutboundMode(surgeMode)
    }

    func setFeature(_ feature: SurgeFeature, enabled: Bool) async throws {
        try await updateFeature(feature, enabled: enabled)
    }

    func dnsCache() async throws -> [String: JSONValue] {
        try await api.get(.dns, query: [], as: [String: JSONValue].self)
    }

    func flushDNS() async throws {
        try await api.post(.dnsFlush)
    }

    func stopEngine() async throws {
        try await api.post(.stop)
    }

    func mitmCertificate() async throws -> Data {
        try await api.getData(.mitmCertificate)
    }

    private func globalPolicy() async throws -> SurgeGlobalPolicyPayload {
        try await api.get(.outboundGlobal, query: [], as: SurgeGlobalPolicyPayload.self)
    }

    private func modules() async throws -> SurgeModulesPayload {
        try await api.get(.modules, query: [], as: SurgeModulesPayload.self)
    }

    private func featureState(_ feature: SurgeFeature) async throws -> SurgeFeaturePayload {
        try await api.get(.feature(feature), query: [], as: SurgeFeaturePayload.self)
    }

    private func configuredFeatureValues() async -> [String: JSONValue] {
        await withTaskGroup(of: (SurgeFeature, Bool?).self) { taskGroup in
            for feature in SurgeFeature.allCases {
                taskGroup.addTask {
                    (feature, try? await featureState(feature).enabled)
                }
            }

            var values: [String: JSONValue] = [:]
            for await (feature, enabled) in taskGroup {
                if let enabled {
                    values[feature.configKey] = .bool(enabled)
                }
            }
            return values
        }
    }

    private func updateFeature(_ feature: SurgeFeature, enabled: Bool) async throws {
        try await api.post(
            .feature(feature),
            body: SurgeFeaturePayload(enabled: enabled)
        )
    }

    private func updateOutboundMode(_ mode: String) async throws {
        try await api.post(.outbound, body: SurgeOutboundUpdate(mode: mode))
    }

    private func updateGlobalPolicy(_ policy: String) async throws {
        try await api.post(
            .outboundGlobal,
            body: SurgeGlobalPolicyUpdate(policy: policy)
        )
    }
}

nonisolated private struct SurgeOutboundUpdate: Encodable, Sendable {
    var mode: String
}

nonisolated private struct SurgeGlobalPolicyUpdate: Encodable, Sendable {
    var policy: String
}
