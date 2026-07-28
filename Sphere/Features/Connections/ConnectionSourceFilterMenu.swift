import SwiftUI

struct ConnectionSourceFilterMenu: View {
    @Binding var selection: String
    var title: String
    var options: [ConnectionSourceFilterOption]

    var body: some View {
        Picker(title, selection: $selection) {
            Text("All")
                .tag("")
            ForEach(options) { option in
                Text(verbatim: option.title)
                    .tag(option.value)
            }
        }
        .disabled(options.isEmpty)
    }
}
