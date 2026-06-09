import Foundation

@MainActor
extension AppModel {
    func upgradeCore(channel: CoreUpdateChannel) async -> CoreUpdateReport {
        guard let client, canUpdateCore else {
            return .skipped(channel: channel)
        }
        isUpdatingCore = true
        defer { isUpdatingCore = false }
        await progressActivityReporter.start(
            kind: .coreUpdate,
            detail: "\(channel.title) channel",
            fraction: ProgressActivityFractions.coreStarted
        )
        do {
            await progressActivityReporter.update(
                kind: .coreUpdate,
                detail: "Downloading \(channel.title.lowercased()) core",
                fraction: ProgressActivityFractions.coreDownloading
            )
            try await client.upgradeCore(channel: channel)
            markBackendConnected()
            await progressActivityReporter.update(
                kind: .coreUpdate,
                detail: "Refreshing backend data",
                fraction: ProgressActivityFractions.coreRefreshing
            )
            await refreshAll()
            await progressActivityReporter.finish(
                kind: .coreUpdate,
                status: .succeeded,
                detail: "Core update finished"
            )
            return .success(channel: channel)
        } catch {
            guard !error.isCancellation else {
                await progressActivityReporter.finish(
                    kind: .coreUpdate,
                    status: .failed,
                    detail: "Core update cancelled"
                )
                return .failure(channel: channel, message: "Cancelled.")
            }
            beginBackendErrorDebounce(error.localizedDescription)
            await progressActivityReporter.finish(
                kind: .coreUpdate,
                status: .failed,
                detail: "Core update failed"
            )
            return .failure(
                channel: channel,
                message: error.localizedDescription
            )
        }
    }
}
