import Foundation

@MainActor
extension AppModel {
    func refreshConnections(source: RefreshSource = .manual) async {
        await loadCachedDataIfNeeded()
        guard let client else { return }
        prepareRefresh(source: source)
        let outcome = await captureErrors {
            updateConnections(try await client.connections())
            saveCachedDataIfUseful()
        }
        await finishRefresh(outcome, source: source)
    }
    
    func closeConnection(_ id: String) async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.closeConnection(id)
            updateConnections(try await client.connections())
            saveCachedDataIfUseful()
        }
    }
    
    func closeAllConnections() async {
        guard let client else { return }
        _ = await captureErrors {
            try await client.closeAllConnections()
            updateConnections(try await client.connections())
            saveCachedDataIfUseful()
        }
    }
}
