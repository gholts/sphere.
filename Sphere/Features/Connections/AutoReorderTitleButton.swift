import SwiftUI

struct AutoReorderTitleButton: View {
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Connections")
                    .font(.headline)
                Image(systemName: isOn ? "stop.circle" : "play.circle")
                    .font(.headline)
                    .foregroundStyle(isOn ? Color.orange : Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Stop auto reorder" : "Start auto reorder")
        .accessibilityHint("Toggles connection auto reorder")
    }
}
