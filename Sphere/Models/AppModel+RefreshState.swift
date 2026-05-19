import Foundation

@MainActor
extension AppModel {
    func result<T: Sendable>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    func apply<T>(_ result: Result<T, Error>, onSuccess: (T) -> Void) -> RefreshOutcome {
        switch result {
        case .success(let value):
            onSuccess(value)
            var outcome = RefreshOutcome()
            outcome.markBackendConnected()
            return outcome
        case .failure(let error):
            return RefreshOutcome(error: error)
        }
    }

    func captureErrors(_ operation: () async throws -> Void) async -> RefreshOutcome {
        do {
            try await operation()
            markBackendConnected()
            var outcome = RefreshOutcome()
            outcome.markBackendConnected()
            return outcome
        } catch {
            guard !error.isCancellation else { return RefreshOutcome() }
            let outcome = RefreshOutcome(error: error)
            beginBackendErrorDebounce(error.localizedDescription)
            return outcome
        }
    }

    func prepareRefresh(source: RefreshSource) {
        if source.isUserInitiated {
            manualRefreshDepth += 1
            isManualRefreshActive = true
            isAutoRefreshSuspended = false
        }
    }

    func finishRefresh(_ outcome: RefreshOutcome, source: RefreshSource) async {
        defer { finishManualRefresh(source: source) }
        if outcome.backendConnected {
            markBackendConnected()
        } else if let message = outcome.errorMessage {
            beginBackendErrorDebounce(message)
        }
        if outcome.connectionFailed {
            suspendBackgroundRefresh()
        } else if source.isUserInitiated {
            isAutoRefreshSuspended = false
        }
        if source.waitsForBackendErrorDebounce {
            await waitForBackendErrorDebounceIfNeeded()
        }
    }

    func suspendBackgroundRefresh() {
        isAutoRefreshSuspended = true
    }

    func finishManualRefresh(source: RefreshSource) {
        guard source.isUserInitiated else { return }
        manualRefreshDepth = max(0, manualRefreshDepth - 1)
        if manualRefreshDepth == 0 {
            isManualRefreshActive = false
        }
    }

    func waitForBackendErrorDebounceIfNeeded() async {
        await runBackendErrorDebounce(revision: backendErrorDebounceRevision)
    }

    func markBackendConnected() {
        backendSuccessGeneration &+= 1
        guard isBackendErrorDebouncing || errorMessage != nil || pendingBackendErrorMessage != nil
        else {
            return
        }
        pendingBackendErrorMessage = nil
        isBackendErrorDebouncing = false
        errorMessage = nil
        backendErrorDebounceRevision &+= 1
    }

    func beginBackendErrorDebounce(_ message: String) {
        pendingBackendErrorMessage = message
        guard !isBackendErrorDebouncing else { return }
        errorMessage = nil
        isBackendErrorDebouncing = true
        backendErrorStartedAtGeneration = backendSuccessGeneration
        backendErrorDebounceRevision &+= 1
    }

    func runBackendErrorDebounce() async {
        await runBackendErrorDebounce(revision: backendErrorDebounceRevision)
    }

    private func runBackendErrorDebounce(revision: Int) async {
        guard isBackendErrorDebouncing, revision == backendErrorDebounceRevision else { return }
        do {
            try await Task.sleep(for: backendErrorDebounceDuration)
        } catch {
            return
        }
        guard revision == backendErrorDebounceRevision else { return }
        confirmBackendError(startedAtGeneration: backendErrorStartedAtGeneration)
    }

    func confirmBackendError(startedAtGeneration generation: Int) {
        guard backendSuccessGeneration == generation else {
            pendingBackendErrorMessage = nil
            isBackendErrorDebouncing = false
            errorMessage = nil
            backendErrorDebounceRevision &+= 1
            return
        }
        errorMessage = pendingBackendErrorMessage
        pendingBackendErrorMessage = nil
        isBackendErrorDebouncing = false
    }
}
