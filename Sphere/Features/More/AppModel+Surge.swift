import Foundation

@MainActor
extension AppModel {
    func loadedSurgeMITMCertificateURL(for profileID: UUID) -> URL? {
        guard
            let profile = selectedProfile,
            profile.kind == .surge,
            profile.id == profileID
        else {
            return nil
        }

        let url = Self.surgeMITMCertificateURL(profileID: profileID)
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = values.fileSize,
            fileSize > 0
        else {
            return nil
        }
        return url
    }

    func prepareSurgeMITMCertificate() async throws -> URL {
        guard
            let profile = selectedProfile,
            profile.kind == .surge,
            let client
        else {
            throw BackendError.unsupportedBackend("Surge MITM CA certificate")
        }
        let profileID = profile.id

        do {
            let data = try await client.mitmCertificate()
            guard selectedProfileID == profileID else { throw CancellationError() }
            guard !data.isEmpty else { throw BackendError.invalidResponse }
            let url = try Self.writeSurgeMITMCertificate(data, profileID: profileID)
            markBackendConnected()
            return url
        } catch {
            guard selectedProfileID == profileID else { throw CancellationError() }
            if !error.isCancellation {
                beginBackendErrorDebounce(error.localizedDescription)
            }
            throw error
        }
    }

    private static func writeSurgeMITMCertificate(
        _ data: Data,
        profileID: UUID
    ) throws -> URL {
        let url = surgeMITMCertificateURL(profileID: profileID)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func surgeMITMCertificateURL(profileID: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "surge-mitm-ca-\(profileID.uuidString).cer")
    }
}
