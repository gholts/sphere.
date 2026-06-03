import Foundation

nonisolated struct SourceIPTag: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var sourceIP: String
    var tag: String

    init(id: UUID, sourceIP: String, tag: String) {
        self.id = id
        self.sourceIP = sourceIP
        self.tag = tag
    }

    init(sourceIP: String, tag: String) {
        self.init(id: UUID(), sourceIP: sourceIP, tag: tag)
    }
}
