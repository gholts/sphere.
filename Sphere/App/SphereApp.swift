import SwiftUI

@main
struct SphereApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await SettingsBundleDefaults.writeAfterInitialRender()
                }
        }
    }
}

private enum SettingsBundleDefaults {
    @MainActor
    static func writeAfterInitialRender() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(200))
        write()
    }

    static func write(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        defaults.set("LAN controller access", forKey: "sphere.settings.localNetworkUse")
        defaults.set(version, forKey: "sphere.settings.version")
        defaults.set("CC BY 4.0", forKey: "sphere.settings.iconLicense")
        defaults.set(
            "Icon illustration by Figma Community author @brixtemplates",
            forKey: "sphere.settings.iconAttribution")
        defaults.set("MIT License", forKey: "sphere.settings.zashboardLicense")
        defaults.set("Zashboard API", forKey: "sphere.settings.zashboardProject")
    }
}
