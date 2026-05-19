import Foundation
import Observation

@Observable
@MainActor
final class ProfileStore {
    var profiles: [APIProfile] = []
    var selectedProfileID: UUID?
    
    @ObservationIgnored private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard, loadsProfilesImmediately: Bool = true) {
        self.defaults = defaults
        if loadsProfilesImmediately {
            loadProfiles()
        }
    }
    
    nonisolated static func decode(_ data: Data) -> [APIProfile] {
        ProfileCodec.decode(data)
    }
    
    nonisolated static func encode(_ profiles: [APIProfile]) -> Data {
        ProfileCodec.encode(profiles)
    }
    
    var selectedProfile: APIProfile? {
        guard let selectedProfileID else {
            return profiles.first
        }
        return profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }
    
    var hasProfiles: Bool {
        !profiles.isEmpty
    }
    
    func loadProfiles() {
        let data = defaults.data(forKey: AppStorageKeys.profiles) ?? Data()
        let storedID = defaults.string(forKey: AppStorageKeys.selectedProfileID)
        applyProfiles(Self.decode(data), storedID: storedID)
    }
    
    func loadProfilesOffMain() async {
        let data = defaults.data(forKey: AppStorageKeys.profiles) ?? Data()
        let storedID = defaults.string(forKey: AppStorageKeys.selectedProfileID)
        let decodedProfiles = await ProfileCodec.decodeAsync(data)
        applyProfiles(decodedProfiles, storedID: storedID)
    }
    
    private func applyProfiles(_ decodedProfiles: [APIProfile], storedID: String?) {
        profiles = decodedProfiles
        if let storedID = storedID.flatMap(UUID.init(uuidString:)) {
            selectedProfileID = storedID
        } else {
            selectedProfileID = profiles.first?.id
        }
    }
    
    func addProfile(_ profile: APIProfile) {
        profiles.append(profile)
        selectedProfileID = profile.id
        saveProfiles()
    }
    
    @discardableResult
    func updateProfile(_ profile: APIProfile) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            addProfile(profile)
            return true
        }
        let oldProfile = profiles[index]
        let wasSelected = selectedProfile?.id == profile.id
        profiles[index] = profile
        if wasSelected {
            selectedProfileID = profile.id
        }
        saveProfiles()
        return wasSelected && (oldProfile.kind != profile.kind || oldProfile.baseURL != profile.baseURL)
    }
    
    @discardableResult
    func deleteProfiles(at offsets: IndexSet) -> Bool {
        let previousSelectedProfileID = selectedProfileID
        for index in offsets.sorted(by: >) {
            profiles.remove(at: index)
        }
        if !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profiles.first?.id
        }
        saveProfiles()
        return selectedProfileID != previousSelectedProfileID
    }
    
    @discardableResult
    func deleteProfile(_ profile: APIProfile) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return false }
        return deleteProfiles(at: IndexSet(integer: index))
    }
    
    func moveProfiles(from offsets: IndexSet, to destination: Int) {
        let movingProfiles = offsets.sorted().map { profiles[$0] }
        for index in offsets.sorted(by: >) {
            profiles.remove(at: index)
        }
        let removedBeforeDestination = offsets.filter { $0 < destination }.count
        profiles.insert(contentsOf: movingProfiles, at: destination - removedBeforeDestination)
        saveProfiles()
    }
    
    @discardableResult
    func selectProfile(_ id: UUID?) -> Bool {
        guard selectedProfileID != id else { return false }
        selectedProfileID = id
        defaults.set(id?.uuidString, forKey: AppStorageKeys.selectedProfileID)
        return true
    }
    
    func saveProfiles() {
        defaults.set(Self.encode(profiles), forKey: AppStorageKeys.profiles)
        defaults.set(selectedProfileID?.uuidString, forKey: AppStorageKeys.selectedProfileID)
    }
}
