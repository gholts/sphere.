import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    let app = PreviewFixtures.app()
    Group {
        // ContentView()
        AppTabView()
            .environment(app)
            .environment(app.liveState)
    }
}
