import Foundation

@MainActor
extension AppModel {
    func surgeDevice(for sourceAddress: String?) -> SurgeDevice? {
        devices.first { $0.matches(sourceAddress: sourceAddress) }
    }

    func sourceDisplayName(for sourceAddress: String?) -> String? {
        if selectedProfile?.kind.supportsDeviceManagement == true {
            return surgeDevice(for: sourceAddress)?.displayName
        }
        return sourceIPTag(for: sourceAddress)
    }

    func renameSurgeDevice(sourceAddress: String, name: String) async {
        guard selectedProfile?.kind.supportsDeviceManagement == true, let client else {
            return
        }
        let profileID = selectedProfileID
        _ = await captureErrors(for: profileID) {
            let currentDevices = devices.isEmpty ? try await client.devices() : devices
            guard selectedProfileID == profileID else { return }
            guard
                let device = currentDevices.first(where: {
                    $0.matches(sourceAddress: sourceAddress)
                }),
                let physicalAddress = device.editablePhysicalAddress
            else {
                throw BackendError.api("No editable Surge device matches \(sourceAddress)")
            }
            try await client.updateDevice(
                SurgeDevice.Update(
                    physicalAddress: physicalAddress,
                    name: name,
                    address: nil,
                    shouldHandledBySurge: nil
                )
            )
            guard selectedProfileID == profileID else { return }
            let nextDevices = try await client.devices()
            guard selectedProfileID == profileID else { return }
            updateDevices(nextDevices)
        }
    }
}
