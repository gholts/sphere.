import SwiftUI

struct ConnectionsSectionHeader: View {
    var visibleCount: Int
    var totalCount: Int

    var body: some View {
        HStack {
            Spacer()
            Text("\(visibleCount)/\(totalCount)")
                .monospacedDigit()
        }
    }
}
