enum RefreshSource {
    case manual
    case automatic
    case pullToRefresh

    var isUserInitiated: Bool {
        self != .automatic
    }

    var waitsForBackendErrorDebounce: Bool {
        self == .pullToRefresh
    }
}
