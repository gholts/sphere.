import Foundation

@MainActor
extension AppModel {
    func downloadSurgeMITMCertificate() async -> URL? {
        guard selectedProfile?.kind == .surge, let client else { return nil }
        do {
            let data = try await client.mitmCertificate()
            let url = try Self.writeSurgeMITMCertificate(data, profileID: selectedProfileID)
            markBackendConnected()
            return url
        } catch {
            beginBackendErrorDebounce(error.localizedDescription)
            return nil
        }
    }

    private static func writeSurgeMITMCertificate(
        _ data: Data,
        profileID: UUID?
    ) throws -> URL {
        let filename = "surge-mitm-ca-\(profileID?.uuidString ?? "default").cer"
        let url = FileManager.default.temporaryDirectory.appending(path: filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
