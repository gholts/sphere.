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
        if let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            defaults.set(version, forKey: "sphere.settings.version")
        }
        defaults.set(
            "GNU General Public License v3.0",
            forKey: "sphere.settings.sphereLicense")
        defaults.set("Hugo Lee", forKey: "sphere.settings.sphereCopyright")
        defaults.set("CC BY 4.0", forKey: "sphere.settings.iconLicense")
        defaults.set(
            "Icon illustration by Figma Community author @brixtemplates",
            forKey: "sphere.settings.iconAttribution")
        defaults.set("MIT License", forKey: "sphere.settings.zashboardLicense")
        defaults.set("MIT License", forKey: "sphere.settings.yasdLicense")
    }
}
