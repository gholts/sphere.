//
//  ContentView.swift
//  Sphere
//
//  Created by Gholts Li on 5/11/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    let app = PreviewFixtures.app()
    Group {
        ContentView()
        AppTabView()
            .environment(app)
            .environment(app.liveState)
    }
}
