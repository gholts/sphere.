import SwiftUI

struct LogBookView: View {
    @Environment(AppModel.self) private var app
    @Environment(LiveState.self) private var logs

    var body: some View {
        List {
            Section("Level") {
                Picker("Level", selection: levelBinding) {
                    ForEach(LogLevel.allCases) { level in
                        Text(level.rawValue.capitalized).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Logs") {
                if logs.logs.isEmpty {
                    Text("Waiting for logs")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs.logs) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.type.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(color(for: entry.type))
                                Spacer()
                                Text(entry.date.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.payload)
                                .font(.system(.footnote, design: .monospaced))
                        }
                    }
                }
            }
        }
        .navigationTitle("Log Book")
        .task(id: LogStreamKey(profileID: app.selectedProfileID, level: logs.logLevel)) {
            await app.streamLogs(level: logs.logLevel)
        }
    }

    private var levelBinding: Binding<LogLevel> {
        Binding(
            get: { logs.logLevel },
            set: {
                logs.logLevel = $0
            }
        )
    }

    private func color(for type: String) -> Color {
        switch type.lowercased() {
        case "error":
            return .red
        case "warning", "warn":
            return .orange
        case "debug":
            return .purple
        default:
            return .secondary
        }
    }
}

private struct LogStreamKey: Equatable {
    var profileID: UUID?
    var level: LogLevel
}
