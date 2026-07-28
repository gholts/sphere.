import SwiftUI

struct RowDisclosureIndicator: View {
    var isExpanded = false

    var body: some View {
        Image(systemName: "chevron.forward")
            .imageScale(.small)
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(.smooth(duration: 0.2), value: isExpanded)
            .accessibilityHidden(true)
    }
}
