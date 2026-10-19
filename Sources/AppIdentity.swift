import Foundation

struct AppIdentity: Equatable {
    let id: String
    let name: String
    let detail: String?
}

/// Uses process ownership and explicit browser labels, never the currently selected tab.
/// A generic WebKit process is not evidence that Safari owns its audio.
enum AppIdentityResolver {
    static let safari = "com.apple.Safari"
    static let safariPreview = "com.apple.SafariTechnologyPreview"

    private static let systemIDs: Set<String> = [
        "com.apple.powerchime", "systemsoundserverd", "com.apple.systemsoundserverd",
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.loginwindow",
        "com.apple.systempreferences", "com.apple.terminal", "com.apple.assistantd",
        "com.apple.sirincservice", "com.apple.siri", "com.apple.corespeech",
        "com.apple.audiomxd", "com.apple.mediaremoted", "com.apple.avconferenced",
        "com.apple.cloudpaird", "com.apple.cmio.continuitycaptureagent",
        "com.apple.accessibility.heard", "com.apple.universalaccessd",
        "com.apple.telephonyutilities", "com.apple.audio.core-audio-driver-service.helper"
    ]

    static func resolve(rawBundle: String, ownerBundle: String?, name: String,
                        regularApp: Bool, bundlePath: String?) -> AppIdentity? {
        let owner = ownerBundle ?? ""
        let raw = rawBundle.lowercased()
        let candidate = owner.isEmpty ? rawBundle : owner
        let lowerName = name.lowercased()
        if systemIDs.contains(raw) || systemIDs.contains(candidate.lowercased()) ||
            candidate.lowercased().hasPrefix("cl.mezcla") ||
            ["powerchime", "systemsoundserverd"].contains(lowerName) { return nil }

        // Safari's GPU/media process is launched by launchd, not parented by Safari.
        // Its localized application name carries the owning browser's identity.
        let webKit = raw.hasPrefix("com.apple.webkit.") || candidate.lowercased().hasPrefix("com.apple.webkit.")
        if candidate == safariPreview || (webKit && lowerName.hasPrefix("safari technology preview ")) {
            return AppIdentity(id: safariPreview, name: "Safari Technology Preview", detail: "Todas las pestañas")
        }
        if candidate == safari || (webKit && (lowerName == "safari" || lowerName.hasPrefix("safari "))) {
            return AppIdentity(id: safari, name: "Safari", detail: "Todas las pestañas")
        }

        // Keep recognizable media apps even when a helper has no Dock presence.
        let mediaApps = ["com.spotify.client": "Spotify", "com.apple.Music": "Música",
                         "com.apple.podcasts": "Podcasts", "com.apple.QuickTimePlayerX": "QuickTime Player",
                         "org.videolan.vlc": "VLC", "com.colliderli.iina": "IINA"]
        if let mediaName = mediaApps[candidate] {
            return AppIdentity(id: candidate, name: mediaName, detail: nil)
        }

        // Ordinary user-facing apps may play media too. Do not surface anonymous
        // processes, background services or unidentified WebKit helpers as apps.
        guard regularApp, !candidate.isEmpty, !candidate.hasPrefix("pid."),
              !candidate.lowercased().hasPrefix("com.apple.webkit."),
              !(bundlePath?.contains("/System/Library/CoreServices/") ?? false) else { return nil }
        let browsers: [String: String] = ["com.google.Chrome": "Google Chrome", "org.mozilla.firefox": "Firefox",
            "com.microsoft.edgemac": "Microsoft Edge", "com.brave.Browser": "Brave", "company.thebrowser.Browser": "Arc"]
        return AppIdentity(id: candidate, name: browsers[candidate] ?? name,
                           detail: browsers[candidate] != nil ? "Todas las pestañas" : nil)
    }
}

enum SettingsMigration {
    /// Copy an old helper's settings only if it maps to exactly one visible app.
    /// Never override preferences already saved under the new, stable app identity.
    static func migrate<T>(_ saved: [String: T], aliases: [String: Set<String>]) -> [String: T] {
        var result = saved
        for oldID in aliases.keys.sorted() {
            guard let targets = aliases[oldID], targets.count == 1, let target = targets.first,
                  target != oldID, result[target] == nil, let value = saved[oldID] else { continue }
            result[target] = value
        }
        return result
    }
}
