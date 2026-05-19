import Foundation

@MainActor
extension AppModel {
    func delayProxyGroups(
        client: any ProxyBackendClient,
        groupNames: [String],
        progress: ((Int, Int) async -> Void)? = nil
    ) async throws -> [String: Int] {
        var mergedDelays: [String: Int] = [:]
        var firstError: Error?
        var successCount = 0
        var startIndex = groupNames.startIndex
        var completedCount = 0

        while startIndex < groupNames.endIndex {
            let endIndex =
                groupNames.index(
                    startIndex, offsetBy: ProxyLatencyTestDefaults.maxConcurrentGroups,
                    limitedBy: groupNames.endIndex) ?? groupNames.endIndex
            let batch = Array(groupNames[startIndex..<endIndex])
            let results = await withTaskGroup(of: Result<[String: Int], Error>.self) { taskGroup in
                for groupName in batch {
                    taskGroup.addTask {
                        do {
                            return .success(
                                try await client.delayProxyGroup(
                                    groupName,
                                    url: ProxyLatencyTestDefaults.url,
                                    timeout: ProxyLatencyTestDefaults.timeout
                                ))
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                var values: [Result<[String: Int], Error>] = []
                for await result in taskGroup {
                    values.append(result)
                }
                return values
            }

            for result in results {
                switch result {
                case .success(let delays):
                    successCount += 1
                    mergedDelays.merge(delays) { _, next in next }
                case .failure(let error):
                    firstError = firstError ?? error
                }
            }
            completedCount += batch.count
            await progress?(completedCount, groupNames.count)
            startIndex = endIndex
        }

        if successCount == 0, let firstError {
            throw firstError
        }
        return mergedDelays
    }
}
