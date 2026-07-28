import SwiftUI

struct ConnectionRawJSONView: View {
    @Environment(\.dismiss) private var dismiss
    var connection: ConnectionInfo

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: connection.rawJSONString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Raw JSON")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
