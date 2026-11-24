import Foundation
import AVFoundation
import UIKit

/// In-app ring buffer of playback / navigation events. Shown in Settings > Playback Diagnostics so a
/// failing site can be diagnosed on the device itself, and copied as a report.
@MainActor
final class DiagnosticsLog: ObservableObject {
    static let shared = DiagnosticsLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let message: String
    }

    @Published private(set) var entries: [Entry] = []
    private let limit = 300

    func add(_ category: String, _ message: String) {
        entries.append(Entry(date: Date(), category: category, message: message))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    func clear() { entries.removeAll() }

    // MARK: Report

    static func audioSessionSummary() -> String {
        let s = AVAudioSession.sharedInstance()
        let outputs = s.currentRoute.outputs.map { "\($0.portType.rawValue)" }.joined(separator: ",")
        return "category=\(s.category.rawValue) mode=\(s.mode.rawValue) otherAudioPlaying=\(s.isOtherAudioPlaying) outputs=[\(outputs)]"
    }

    func report(session: MediaSession?, tabs: Int) -> String {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var lines: [String] = []
        lines.append("KingVid \(version) · iOS \(os) · \(UIDevice.current.model)")
        lines.append("User agent suffix: \(WebViewFactory.userAgentSuffix)")
        lines.append("Audio session: \(Self.audioSessionSummary())")
        lines.append("Settings: bg=\(Prefs.backgroundPlayback) spoofVisibility=\(Prefs.spoofVisibility) autoResume=\(Prefs.autoResume) keepAlive=\(Prefs.keepAlive) autoPiP=\(Prefs.autoPiP) lockScreen=\(Prefs.lockScreenControls) ytHideChrome=\(Prefs.ytHideChrome)")
        lines.append("Browser tabs: \(tabs)")
        if let s {
            lines.append("Media session: playing=\(s.isPlaying) video=\(s.isVideo) live=\(s.isLive) pip=\(s.pipActive) pos=\(Int(s.position))/\(Int(s.duration)) host=\(s.host) title=\(s.title)")
        } else {
            lines.append("Media session: none")
        }
        lines.append("")
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        for e in entries.suffix(120) {
            lines.append("[\(formatter.string(from: e.date))] \(e.category): \(e.message)")
        }
        return lines.joined(separator: "\n")
    }
}
