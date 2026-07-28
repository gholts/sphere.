import SwiftUI

struct ConnectionIconText: View {
    var systemImage: String
    var title: String

    var body: some View {
        Label {
            Text(verbatim: title)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}
