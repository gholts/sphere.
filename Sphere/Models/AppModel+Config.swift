import Foundation

@MainActor
extension AppModel {
    func loadConfig() async {
        guard let client else { return }
        _ = await captureErrors {
            applyConfigs(try await client.configs())
            saveCachedDataIfUseful()
        }
    }
    
    func patchConfig(_ changedValues: [String: JSONValue]) async -> Bool {
        guard let client else { return false }
        let outcome = await captureErrors {
            try await client.patchConfigs(changedValues)
            applyConfigs(try await client.configs())
            saveCachedDataIfUseful()
        }
        return outcome.errorMessage == nil
    }
    
    func reloadConfig() async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.reloadConfig()
            applyConfigs(try await client.configs())
            saveCachedDataIfUseful()
        }
    }
    
    func updateMode(_ mode: ClashMode) async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.updateClashMode(mode)
            clashMode = mode
            applyConfigs(try await client.configs())
            saveCachedDataIfUseful()
        }
    }
}
