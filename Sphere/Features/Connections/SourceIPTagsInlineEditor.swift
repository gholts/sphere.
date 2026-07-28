import SwiftUI

struct SourceIPTagsInlineEditor: View {
    @Environment(AppModel.self) private var app
    var sourceIPs: [String]

    var body: some View {
        DisclosureGroup {
            if sourceIPs.isEmpty {
                Label("No Source IPs", systemImage: "tag.slash")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sourceIPs, id: \.self) { sourceIP in
                    SourceIPTagEditorRow(
                        sourceIP: sourceIP,
                        initialTag: app.sourceIPTag(for: sourceIP) ?? ""
                    )
                }
            }
        } label: {
            Label("Source IP Tags", systemImage: "tag")
        }
    }
}
