import Foundation

@main
struct IdentityTests {
    static func main() {
        func resolve(_ bundle: String, _ name: String, regular: Bool = false, owner: String? = nil, path: String? = nil) -> AppIdentity? {
            AppIdentityResolver.resolve(rawBundle: bundle, ownerBundle: owner ?? bundle, name: name, regularApp: regular, bundlePath: path)
        }
        for bundle in ["com.apple.PowerChime", "systemsoundserverd", "com.apple.systemsoundserverd", "com.apple.controlcenter", "com.apple.assistantd", "com.apple.loginwindow", "com.apple.Terminal"] {
            precondition(resolve(bundle, bundle, regular: true) == nil, "System audio leaked: \(bundle)")
        }
        precondition(resolve("", "Proceso 42") == nil)
        precondition(resolve("com.vendor.agent", "Background Helper") == nil)
        precondition(resolve("com.apple.WebKit.GPU", "Safari Graphics and Media") == AppIdentity(id: "com.apple.Safari", name: "Safari", detail: "Todas las pestañas"))
        precondition(resolve("com.apple.WebKit.GPU", "Safari Technology Preview Graphics and Media")?.id == "com.apple.SafariTechnologyPreview")
        precondition(resolve("com.apple.WebKit.GPU", "WebKit GPU") == nil, "Do not attribute every WebKit client to Safari")
        precondition(resolve("com.apple.WebKit.GPU", "Other Browser", regular: true, owner: "org.other.browser")?.id == "org.other.browser")
        precondition(resolve("com.apple.Safari", "Safari", regular: true)?.name == "Safari")
        precondition(resolve("com.apple.Music", "Music", regular: true)?.name == "Música")
        precondition(resolve("com.spotify.client", "Spotify")?.id == "com.spotify.client")
        precondition(resolve("com.google.Chrome.helper", "Google Chrome", regular: true, owner: "com.google.Chrome")?.id == "com.google.Chrome")
        precondition(resolve("com.vendor.Player", "Player", regular: true)?.name == "Player")
        precondition(resolve("com.vendor.Agent", "Agent", regular: true, path: "/System/Library/CoreServices/Agent.app") == nil)

        let old = ["com.apple.WebKit.GPU": "55-percent-muted-JBL", "com.spotify.client": "unchanged"]
        let migration = SettingsMigration.migrate(old, aliases: ["com.apple.WebKit.GPU": ["com.apple.Safari"]])
        precondition(migration["com.apple.Safari"] == old["com.apple.WebKit.GPU"])
        precondition(migration["com.spotify.client"] == "unchanged")
        precondition(SettingsMigration.migrate(migration, aliases: ["com.apple.WebKit.GPU": ["com.apple.Safari"]]) == migration)
        let explicit = ["com.apple.WebKit.GPU": "old", "com.apple.Safari": "new"]
        precondition(SettingsMigration.migrate(explicit, aliases: ["com.apple.WebKit.GPU": ["com.apple.Safari"]]) == explicit)
        precondition(SettingsMigration.migrate(old, aliases: ["com.apple.WebKit.GPU": ["com.apple.Safari", "org.other.browser"]]) == old)
        print("PASS: system filtering, Safari grouping, browser ownership, media apps, preference migration and ambiguous helper protection.")
    }
}
