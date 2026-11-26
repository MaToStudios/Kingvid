import Foundation

/// Keys for every user preference. Views bind with `@AppStorage(SettingsKey.x)`,
/// non-view code reads through `Prefs` so the defaults live in exactly one place.
enum SettingsKey {
    // Background playback
    static let backgroundPlayback = "bg.enabled"
    static let spoofVisibility = "bg.spoofVisibility"
    static let autoResume = "bg.autoResume"
    static let keepAlive = "bg.keepAlive"
    static let resumeAfterInterruption = "bg.resumeAfterInterruption"
    // Picture in Picture
    static let autoPiP = "pip.auto"
    // YouTube
    static let ytHideChrome = "yt.hideChrome"
    static let ytRecentSearches = "yt.recentSearches"
    // Lock screen
    static let lockScreenControls = "lock.enabled"
    static let skipInterval = "lock.skipInterval"
    // Browser
    static let searchEngine = "browser.searchEngine"
    static let desktopMode = "browser.desktopMode"
    static let blockPopups = "browser.blockPopups"
    static let saveHistory = "browser.saveHistory"
    static let homepage = "browser.homepage"
    // Appearance
    static let appearanceBackground = "appearance.background"
    static let appearanceAccent = "appearance.accent"
}

enum Prefs {
    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        let d = UserDefaults.standard
        return d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
    }

    static var backgroundPlayback: Bool { bool(SettingsKey.backgroundPlayback, true) }
    static var spoofVisibility: Bool { bool(SettingsKey.spoofVisibility, true) }
    static var autoResume: Bool { bool(SettingsKey.autoResume, true) }
    static var keepAlive: Bool { bool(SettingsKey.keepAlive, true) }
    static var resumeAfterInterruption: Bool { bool(SettingsKey.resumeAfterInterruption, true) }
    /// Off by default: iOS only allows automatic PiP in limited situations, so the PiP button is the reliable way.
    static var autoPiP: Bool { bool(SettingsKey.autoPiP, false) }
    static var ytHideChrome: Bool { bool(SettingsKey.ytHideChrome, true) }
    static var lockScreenControls: Bool { bool(SettingsKey.lockScreenControls, true) }
    static var skipInterval: Double {
        let v = UserDefaults.standard.double(forKey: SettingsKey.skipInterval)
        return v > 0 ? v : 15
    }
    static var desktopMode: Bool { bool(SettingsKey.desktopMode, false) }
    static var blockPopups: Bool { bool(SettingsKey.blockPopups, true) }
    static var saveHistory: Bool { bool(SettingsKey.saveHistory, true) }
    static var homepage: String {
        UserDefaults.standard.string(forKey: SettingsKey.homepage)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
