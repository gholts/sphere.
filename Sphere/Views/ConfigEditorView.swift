import SwiftUI

struct ConfigEditorView: View {
    @Environment(AppModel.self) private var app
    @State private var draft: [String: String] = [:]
    @State private var isLoadingConfig = false

    private var configSections: [BackendConfigSection] {
        BackendConfigCatalog.sections(for: app.selectedProfile?.kind, configs: app.configs)
    }

    private var editableFields: [BackendConfigField] {
        configSections.flatMap(\.fields)
    }

    private var changedValues: [String: JSONValue] {
        editableFields.reduce(into: [:]) { result, field in
            guard
                let original = app.configs.value(at: field.path),
                let text = draft[field.id]
            else { return }
            let parsed = field.control.parsedValue(from: text, fallback: original)
            if parsed != original {
                result.mergeConfigPatch(path: field.path, value: parsed, originals: app.configs)
            }
        }
    }

    var body: some View {
        List {
            if isLoadingConfig, app.configs.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else if app.configs.isEmpty {
                EmptyStateView(title: "No Config", message: "Refresh config or check backend connection.", systemImage: "slider.horizontal.3")
                    .listRowBackground(Color.clear)
            } else if configSections.isEmpty {
                EmptyStateView(title: "No Editable Config", message: "Backend returned no supported `/configs` keys.", systemImage: "slider.horizontal.3")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(configSections) { section in
                    Section(section.title) {
                        ForEach(section.fields) { field in
                            if let value = app.configs.value(at: field.path) {
                                ConfigFieldRow(
                                    field: field,
                                    value: value,
                                    text: binding(for: field, value: value)
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Advanced Config")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    DisabledAwareActionIcon(
                        systemImage: "arrow.triangle.2.circlepath",
                        isEnabled: !isLoadingConfig
                    )
                }
                .accessibilityLabel("Reload config")
                .disabled(isLoadingConfig)

                Button {
                    Task { await save() }
                } label: {
                    DisabledAwareActionIcon(
                        systemImage: "checkmark",
                        isEnabled: !changedValues.isEmpty
                    )
                }
                .disabled(changedValues.isEmpty)
                .accessibilityLabel("Save config")
            }
        }
        .task(id: app.selectedProfileID) {
            await load()
        }
        .onChange(of: app.configs) {
            pruneDraft()
        }
    }

    private func binding(for field: BackendConfigField, value: JSONValue) -> Binding<String> {
        Binding(
            get: { draft[field.id] ?? field.control.displayText(for: value) },
            set: { draft[field.id] = $0 }
        )
    }

    private func load() async {
        isLoadingConfig = true
        await app.loadConfig()
        isLoadingConfig = false
        pruneDraft()
    }

    private func save() async {
        if await app.patchConfig(changedValues) {
            pruneDraft()
        }
    }

    private func reload() async {
        isLoadingConfig = true
        await app.reloadConfig()
        isLoadingConfig = false
        pruneDraft()
    }

    private func pruneDraft() {
        let validKeys = Set(editableFields.map(\.id))
        draft = draft.filter { key, _ in validKeys.contains(key) }
    }
}

private struct ConfigFieldRow: View {
    var field: BackendConfigField
    var value: JSONValue
    @Binding var text: String

    var body: some View {
        switch field.control {
        case .toggle:
            Toggle(isOn: boolBinding) {
                ConfigFieldLabel(title: field.title)
            }
        case .picker:
            Picker(selection: $text) {
                ForEach(field.control.pickerOptions(containing: text), id: \.self) { option in
                    Text(option.isEmpty ? "Default" : option).tag(option)
                }
            } label: {
                ConfigFieldLabel(title: field.title)
            }
        case .number:
            HStack {
                ConfigFieldLabel(title: field.title)
                TextField(value.displayText, text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
            }
        case .text:
            HStack {
                ConfigFieldLabel(title: field.title)
                TextField(value.displayText, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
        case .longText:
            NavigationLink {
                ConfigTextDetailEditor(title: field.title, text: $text, isMonospaced: true)
            } label: {
                detailLabel(summary: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Empty" : "Set")
            }
        case .stringList, .numberList:
            NavigationLink {
                ConfigTextDetailEditor(title: field.title, text: $text, isMonospaced: true)
            } label: {
                detailLabel(summary: listSummary)
            }
        case .json:
            NavigationLink {
                ConfigTextDetailEditor(title: field.title, text: $text, isMonospaced: true)
            } label: {
                detailLabel(summary: value.displayText)
            }
        }
    }

    private func detailLabel(summary: String) -> some View {
        HStack {
            ConfigFieldLabel(title: field.title)
            Spacer()
            Text(summary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { ["true", "1", "yes", "on"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) },
            set: { text = $0 ? "true" : "false" }
        )
    }

    private var listSummary: String {
        let count = text
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        return count == 0 ? "Empty" : "\(count) items"
    }
}

private struct ConfigTextDetailEditor: View {
    var title: String
    @Binding var text: String
    var isMonospaced: Bool

    var body: some View {
        TextEditor(text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(isMonospaced ? .body.monospaced() : .body)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConfigFieldLabel: View {
    var title: String

    var body: some View {
        Text(title)
            .foregroundStyle(.primary)
    }
}
