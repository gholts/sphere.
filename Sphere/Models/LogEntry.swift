import Foundation

nonisolated struct LogEntry: Identifiable, Decodable, Equatable, Sendable {
    var id = UUID()
    var type: String
    var payload: String
    var date = Date()

    enum CodingKeys: String, CodingKey {
        case type
        case payload
    }
}
