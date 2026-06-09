import Foundation

@MainActor
extension AppModel {
    func loadProfiles() {
        profileStore.loadProfiles()
    }

    func loadProfilesOffMain() async {
        await profileStore.loadProfilesOffMain()
    }

    func addProfile(_ profile: APIProfile) {
        profileStore.addProfile(profile)
        selectedTab = .proxies
    }

    func updateProfile(_ profile: APIProfile) {
        let shouldReset = profileStore.updateProfile(profile)
        if shouldReset {
            defaults.removeObject(forKey: cacheKey(profileID: profile.id))
            resetLoadedData()
        }
    }

    func deleteProfiles(at offsets: IndexSet) {
        flushPendingCacheSave()
        if profileStore.deleteProfiles(at: offsets) {
            resetLoadedData()
        }
    }

    func deleteProfile(_ profile: APIProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        deleteProfiles(at: IndexSet(integer: index))
    }

    func moveProfiles(from offsets: IndexSet, to destination: Int) {
        profileStore.moveProfiles(from: offsets, to: destination)
    }

    func selectProfile(_ id: UUID?) {
        flushPendingCacheSave()
        guard profileStore.selectProfile(id) else { return }
        resetLoadedData()
    }

    func saveProfiles() {
        profileStore.saveProfiles()
    }

    func testProfile(_ profile: APIProfile) async throws -> BackendOverview {
        try await makeClient(profile).testConnection()
    }
}
