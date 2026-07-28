import Foundation

@MainActor
extension AppModel {
    func refreshConnections() async {
        await refreshConnections(source: .manual)
    }

    func refreshConnections(source: RefreshSource) async {
        await loadCachedDataIfNeeded()
        guard let client else { return }
        let profileID = selectedProfileID
        let supportsDeviceManagement =
            selectedProfile?.kind.supportsDeviceManagement == true
        prepareRefresh(source: source)
        let connectionsResult = await result { try await client.connections() }
        guard selectedProfileID == profileID else {
            finishManualRefresh(source: source)
            return
        }
        var outcome = apply(connectionsResult) {
            updateConnections($0)
        }
        if supportsDeviceManagement {
            let devicesResult = await result { try await client.devices() }
            guard selectedProfileID == profileID else {
                finishManualRefresh(source: source)
                return
            }
            outcome.merge(
                apply(devicesResult) {
                    updateDevices($0)
                }
            )
        } else {
            updateDevices([])
        }
        await finishRefresh(outcome, source: source)
    }

    func closeConnection(_ id: String) async {
        guard let client else { return }
        let profileID = selectedProfileID
        _ = await captureErrors(for: profileID) {
            try await client.closeConnection(id)
            guard selectedProfileID == profileID else { return }
            updateConnections(try await client.connections())
        }
    }

    func closeAllConnections() async {
        guard let client else { return }
        let profileID = selectedProfileID
        _ = await captureErrors(for: profileID) {
            try await client.closeAllConnections()
            guard selectedProfileID == profileID else { return }
            updateConnections(try await client.connections())
        }
    }

    @discardableResult
    func updateDevice(_ update: SurgeDevice.Update) async -> RefreshOutcome {
        guard selectedProfile?.kind.supportsDeviceManagement == true, let client else {
            return RefreshOutcome(
                error: BackendError.unsupportedBackend("Surge device update")
            )
        }
        let profileID = selectedProfileID
        return await captureErrors(for: profileID) {
            try await client.updateDevice(update)
            guard selectedProfileID == profileID else { return }
            let nextDevices = try await client.devices()
            guard selectedProfileID == profileID else { return }
            updateDevices(nextDevices)
        }
    }
}
