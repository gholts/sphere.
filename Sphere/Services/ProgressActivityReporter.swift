import ActivityKit
import Foundation

@MainActor
protocol ProgressActivityReporting {
    func start(kind: SphereProgressActivityKind, title: String, detail: String, fraction: Double) async
    func update(title: String, detail: String, fraction: Double) async
    func finish(status: SphereProgressActivityStatus, title: String, detail: String) async
}

extension ProgressActivityReporting {
    func start(kind: SphereProgressActivityKind, detail: String, fraction: Double) async {
        await start(kind: kind, title: kind.title, detail: detail, fraction: fraction)
    }

    func update(kind: SphereProgressActivityKind, detail: String, fraction: Double) async {
        await update(title: kind.title, detail: detail, fraction: fraction)
    }

    func finish(kind: SphereProgressActivityKind, status: SphereProgressActivityStatus, detail: String) async {
        await finish(status: status, title: kind.title, detail: detail)
    }
}

enum ProgressActivityFractions {
    static let coreStarted = 0.08
    static let coreDownloading = 0.35
    static let coreRefreshing = 0.85
    static let latencyGroupTestingWeight = 0.9
    static let latencyRefreshing = 0.95
}

struct NoopProgressActivityReporter: ProgressActivityReporting {
    func start(kind: SphereProgressActivityKind, title: String, detail: String, fraction: Double) async {}
    func update(title: String, detail: String, fraction: Double) async {}
    func finish(status: SphereProgressActivityStatus, title: String, detail: String) async {}
}

enum ProgressActivityReporterFactory {
    static func makeDefault() -> any ProgressActivityReporting {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return NoopProgressActivityReporter()
        }
        return LiveActivityProgressReporter()
    }
}

@MainActor
final class LiveActivityProgressReporter: ProgressActivityReporting {
    private var activity: Activity<SphereProgressActivityAttributes>?

    func start(kind: SphereProgressActivityKind, title: String, detail: String, fraction: Double) async {
        await endCurrent()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = SphereProgressActivityAttributes(
            operationID: UUID().uuidString,
            kind: kind
        )
        let content = activityContent(
            title: title,
            detail: detail,
            fraction: fraction,
            status: .running
        )

        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            activity = nil
        }
    }

    func update(title: String, detail: String, fraction: Double) async {
        guard let activity else { return }
        let content = activityContent(
            title: title,
            detail: detail,
            fraction: fraction,
            status: .running
        )
        await activity.update(content)
    }

    func finish(status: SphereProgressActivityStatus, title: String, detail: String) async {
        guard let activity else { return }
        let content = activityContent(
            title: title,
            detail: detail,
            fraction: 1,
            status: status
        )
        await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(ProgressActivityTiming.finishedDismissalDelay)))
        self.activity = nil
    }

    private func endCurrent() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }

    private func activityContent(
        title: String,
        detail: String,
        fraction: Double,
        status: SphereProgressActivityStatus
    ) -> ActivityContent<SphereProgressActivityAttributes.ContentState> {
        ActivityContent(
            state: SphereProgressActivityAttributes.ContentState(
                title: title,
                detail: detail,
                fraction: fraction,
                status: status
            ),
            staleDate: Date().addingTimeInterval(ProgressActivityTiming.staleInterval),
            relevanceScore: 1
        )
    }
}

private enum ProgressActivityTiming {
    static let staleInterval: TimeInterval = 15 * 60
    static let finishedDismissalDelay: TimeInterval = 12
}
