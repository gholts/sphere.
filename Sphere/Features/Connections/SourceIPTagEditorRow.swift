import SwiftUI

struct SourceIPTagEditorRow: View {
    @Environment(AppModel.self) private var app
    @State private var tag: String

    var sourceIP: String

    init(sourceIP: String, initialTag: String) {
        self.sourceIP = sourceIP
        _tag = State(initialValue: initialTag)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: sourceIP)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                TextField("Tag", text: $tag)
                    .textInputAutocapitalization(.never)
                    .onSubmit(saveTag)
                    .onChange(of: tag) { _, _ in
                        saveTag()
                    }

                if !tag.isEmpty {
                    Button("Clear", systemImage: "xmark.circle", action: clearTag)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Clear tag for \(sourceIP)")
                }
            }
        }
        .onChange(of: sourceIP) { _, _ in
            tag = app.sourceIPTag(for: sourceIP) ?? ""
        }
    }

    private func saveTag() {
        app.setSourceIPTag(tag, for: sourceIP)
    }

    private func clearTag() {
        tag = ""
        app.removeSourceIPTag(for: sourceIP)
    }
}
