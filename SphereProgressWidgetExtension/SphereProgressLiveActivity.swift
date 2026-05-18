import ActivityKit
import SwiftUI
import WidgetKit

struct SphereProgressLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SphereProgressActivityAttributes.self) { context in
            SphereProgressLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.title, systemImage: context.attributes.kind.systemImage)
                        .font(.caption)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.percentText)
                        .font(.caption.monospacedDigit())
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: context.state.clampedFraction)
                            .tint(activityTint(for: context.state.status))
                        Text(context.state.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.kind.systemImage)
                    .foregroundStyle(activityTint(for: context.state.status))
            } compactTrailing: {
                Text(context.state.percentText)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: minimalImage(for: context.state.status, kind: context.attributes.kind))
                    .foregroundStyle(activityTint(for: context.state.status))
            }
        }
    }
}

private struct SphereProgressLockScreenView: View {
    let context: ActivityViewContext<SphereProgressActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.attributes.kind.systemImage)
                .font(.title3)
                .foregroundStyle(activityTint(for: context.state.status))
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(context.state.title)
                        .font(.headline)
                    Spacer()
                    Text(context.state.percentText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: context.state.clampedFraction)
                    .tint(activityTint(for: context.state.status))
                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
    }
}

private func activityTint(for status: SphereProgressActivityStatus) -> Color {
    switch status {
    case .running:
        return .accentColor
    case .succeeded:
        return .green
    case .failed:
        return .red
    }
}

private func minimalImage(
    for status: SphereProgressActivityStatus,
    kind: SphereProgressActivityKind
) -> String {
    switch status {
    case .running:
        return kind.systemImage
    case .succeeded:
        return "checkmark.circle.fill"
    case .failed:
        return "xmark.circle.fill"
    }
}
