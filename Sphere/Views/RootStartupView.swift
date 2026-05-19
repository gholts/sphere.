import SwiftUI

struct RootStartupView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .accessibilityLabel("Starting Sphere")
    }
}
