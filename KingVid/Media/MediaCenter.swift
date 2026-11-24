import SwiftUI
import AVFoundation
import AVKit
import MediaPlayer
import WebKit

/// Snapshot of the page's primary media element, as reported by the injected script.
struct MediaSession: Equatable {
    var tabID: UUID
    var title: String
    var artist: String
    var host: String
    var pageURL: URL?
    var artworkURL: URL?
    var duration: Double
    var position: Double
    var rate: Double
    var isPlaying: Bool
    var isVideo: Bool
    var isLive: Bool
    var pipActive: Bool
    var hasNext: Bool
    var hasPrevious: Bool
}

/// Which tab currently owns the media session. Separate from `MediaCenter` so views that only need the
/// owner (to keep its web view attached) don't re-render every second when playback position ticks.
@MainActor
final class MediaOwnership: ObservableObject {
    @Published var tabID: UUID?
}

/// Central coordinator for media playback: owns the audio session, Now Playing info,
/// Lock Screen / Control Center commands, interruption + background handling and PiP triggers.
///
/// Playback itself always stays in the website's original player; this class only observes it
/// (via the `kvMedia` script messages) and controls it (via `window.__kv.cmd`).
@MainActor
final class MediaCenter: ObservableObject {
    @Published private(set) var session: MediaSession?
    @Published private(set) var artwork: UIImage?
    /// Last media failure reported by a page's player (cleared when playback next starts).
    @Published private(set) var lastError: String?
    let pipSupported = AVPictureInPictureController.isPictureInPictureSupported()
    let ownership = MediaOwnership()

    /// Every web view that can own playback (browser tabs + YouTube views). Set by `AppModel`.
    var allTabs: () -> [BrowserTab] = { [] }
    private let library: LibraryStore
    private var loggedHosts = Set<String>()

    private var activeFrame: WKFrameInfo?
    private var remote: RemoteCommands?
    private let keepAlive = SilentKeepAlive()
    private var keepAliveStopTask: Task<Void, Never>?

    private var artworkURL: URL?
    private var artworkTask: Task<Void, Never>?
    private var artworkCache: [URL: UIImage] = [:]

    private var autoPiPStarted = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lastPersistAt = Date.distantPast
    private var lastPersistKey = ""

    init(library: LibraryStore) {
        self.library = library
        configureAudioSessionCategory()

        remote = RemoteCommands { [weak self] action in
            Task { @MainActor in self?.perform(action) }
        }
        remote?.configure(enabled: false, hasNext: false, hasPrevious: false, live: false, skipInterval: Prefs.skipInterval)
        observeSystemNotifications()
    }

    private func findTab(_ id: UUID) -> BrowserTab? { allTabs().first { $0.id == id } }

    // MARK: - Incoming messages from pages

    func handle(_ body: [String: Any], from tab: BrowserTab, frame: WKFrameInfo) {
        // The YouTube browse view never owns playback; videos open in the dedicated player view.
        guard tab.kind != .youtubeBrowse else { return }
        switch body["type"] as? String {
        case "mediaError":
            handleMediaError(body, from: tab)
            return
        case "diag":
            handleDiag(body)
            return
        case "state":
            break
        default:
            return
        }

        let paused = (body["paused"] as? Bool) ?? true
        let ended = (body["ended"] as? Bool) ?? false
        let playing = !paused && !ended

        // A different tab's idle/paused chatter must not hijack the current session.
        if let current = session, current.tabID != tab.id, !playing { return }

        func number(_ key: String, _ fallback: Double = 0) -> Double {
            let v = (body[key] as? NSNumber)?.doubleValue ?? fallback
            return v.isFinite ? v : fallback
        }

        let host = (body["host"] as? String) ?? ""
        let artworkString = (body["artwork"] as? String) ?? ""
        let updated = MediaSession(
            tabID: tab.id,
            title: Self.cleanTitle((body["title"] as? String) ?? "", host: host),
            artist: (body["artist"] as? String) ?? host,
            host: host,
            pageURL: (body["url"] as? String).flatMap { URL(string: $0) },
            artworkURL: artworkString.isEmpty ? nil : URL(string: artworkString),
            duration: number("duration"),
            position: number("position"),
            rate: max(0.1, number("rate", 1)),
            isPlaying: playing,
            isVideo: (body["isVideo"] as? Bool) ?? false,
            isLive: (body["live"] as? Bool) ?? false,
            pipActive: (body["pip"] as? Bool) ?? false,
            hasNext: (body["hasNext"] as? Bool) ?? false,
            hasPrevious: (body["hasPrev"] as? Bool) ?? false
        )

        let previous = session
        if let previous, previous.tabID != tab.id {
            // A new tab took over: stop the old one so two sites never play at once.
            findTab(previous.tabID)?.runKV("cmd('pause')")
        }
        if previous?.tabID != tab.id { ownership.tabID = tab.id }
        activeFrame = frame
        if updated.isPlaying { lastError = nil }
        if previous?.isPlaying != updated.isPlaying {
            DiagnosticsLog.shared.add("media", "\(updated.isPlaying ? "playing" : "paused") · \(updated.host) · \(updated.isVideo ? "video" : "audio") · \(Int(updated.position))/\(Int(updated.duration))s")
        }

        if previous != updated { session = updated }
        loadArtwork(updated.artworkURL)
        playbackStateChanged(wasPlaying: previous?.isPlaying ?? false, session: updated)
        updateNowPlaying()
        persistRecent(updated, wasPlaying: previous?.isPlaying ?? false)
    }

    private func handleMediaError(_ body: [String: Any], from tab: BrowserTab) {
        let code = (body["code"] as? NSNumber)?.intValue ?? 0
        let host = (body["host"] as? String) ?? tab.url?.host ?? ""
        let meaning: String
        switch code {
        case 1: meaning = "playback aborted"
        case 2: meaning = "network error"
        case 3: meaning = "decode error"
        case 4: meaning = "format not supported"
        default: meaning = "unknown error"
        }
        let detail = (body["message"] as? String) ?? ""
        DiagnosticsLog.shared.add("media", "ERROR \(host): \(meaning) (code \(code)) \(detail)")
        // Only surface it for the tab the user is actually watching.
        if session?.tabID == tab.id || tab.kind == .youtubePlayer {
            lastError = "\(host): \(meaning)"
        }
    }

    private func handleDiag(_ body: [String: Any]) {
        let host = (body["host"] as? String) ?? ""
        guard !host.isEmpty, loggedHosts.insert(host).inserted else { return }
        DiagnosticsLog.shared.add("page", "\(host) · MediaSource=\(body["mse"] ?? "?") ManagedMediaSource=\(body["mms"] ?? "?") HLS=\(body["hls"] ?? "?") mp4=\(body["mp4"] ?? "?") webm=\(body["webm"] ?? "?")")
    }

    private static func cleanTitle(_ raw: String, host: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" - YouTube Music", " - YouTube", " | SoundCloud", " | Vimeo", " - Dailymotion"] where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
        }
        return title.isEmpty ? host : title
    }

    // MARK: - Commands (mini-player, player sheet, lock screen)

    func perform(_ action: RemoteAction) {
        switch action {
        case .play: play()
        case .pause: pause()
        case .toggle: toggle()
        case .next: send("next")
        case .previous: send("prev")
        case .skip(let seconds): skip(seconds)
        case .seek(let time): seek(to: time)
        }
    }

    func play() { send("play") }
    func pause() { send("pause") }
    func toggle() { (session?.isPlaying ?? false) ? pause() : play() }
    func skip(_ seconds: Double) { send("skip", seconds) }
    func seek(to time: Double) { send("seek", time) }
    func setRate(_ rate: Double) { send("rate", rate) }
    func togglePiP() { send("pip") }
    func next() { send("next") }
    func previous() { send("prev") }

    /// Stops playback and dismisses the mini-player.
    func closeSession() {
        guard let current = session else { return }
        findTab(current.tabID)?.runKV("cmd('pause')", frame: activeFrame)
        clearSession()
    }

    func tabClosed(_ id: UUID) {
        if session?.tabID == id { clearSession() }
    }

    /// A full page navigation destroys the media element, so the session is stale.
    func tabNavigated(_ id: UUID) {
        if session?.tabID == id { clearSession() }
    }

    private func clearSession() {
        session = nil
        artwork = nil
        artworkURL = nil
        activeFrame = nil
        ownership.tabID = nil
        keepAlive.stop()
        keepAliveStopTask?.cancel()
        updateNowPlaying()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func send(_ command: String, _ argument: Double? = nil) {
        guard let current = session, let tab = findTab(current.tabID) else { return }
        let arg: String
        if let argument, argument.isFinite { arg = ", \(argument)" } else { arg = "" }
        tab.runKV("cmd('\(command)'\(arg))", frame: activeFrame)
    }

    // MARK: - Audio session

    private func configureAudioSessionCategory() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .moviePlayback, options: [])
    }

    private func activateAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .moviePlayback, options: [])
        try? audio.setActive(true)
    }

    private func playbackStateChanged(wasPlaying: Bool, session: MediaSession) {
        if session.isPlaying {
            keepAliveStopTask?.cancel()
            if !wasPlaying { activateAudioSession() }
            if Prefs.keepAlive { keepAlive.start() }
        } else if wasPlaying {
            // Give the user two minutes to resume from the Lock Screen before releasing the process.
            keepAliveStopTask?.cancel()
            keepAliveStopTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard !Task.isCancelled else { return }
                self?.keepAlive.stop()
            }
        }
    }

    // MARK: - Now Playing / Lock Screen

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard Prefs.lockScreenControls, let s = session else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            remote?.configure(enabled: false, hasNext: false, hasPrevious: false, live: false,
                              skipInterval: Prefs.skipInterval)
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: s.title,
            MPMediaItemPropertyArtist: s.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: s.position,
            MPNowPlayingInfoPropertyPlaybackRate: s.isPlaying ? s.rate : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyIsLiveStream: s.isLive,
            MPNowPlayingInfoPropertyMediaType: (s.isVideo ? MPNowPlayingInfoMediaType.video : MPNowPlayingInfoMediaType.audio).rawValue
        ]
        if !s.isLive, s.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = s.duration
        }
        info[MPMediaItemPropertyArtwork] = RemoteCommands.makeArtwork(artwork ?? CrownArtwork.image)

        center.nowPlayingInfo = info
        center.playbackState = s.isPlaying ? .playing : .paused
        remote?.configure(enabled: true, hasNext: s.hasNext, hasPrevious: s.hasPrevious,
                          live: s.isLive, skipInterval: Prefs.skipInterval)
    }

    private func loadArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        artworkTask?.cancel()
        artwork = nil
        guard let url else { return }
        if let cached = artworkCache[url] {
            artwork = cached
            return
        }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled, let image = UIImage(data: data) else { return }
            guard let self, self.artworkURL == url else { return }
            self.artworkCache[url] = image
            self.artwork = image
            self.updateNowPlaying()
        }
    }

    // MARK: - Recently played

    private func persistRecent(_ s: MediaSession, wasPlaying: Bool) {
        guard let url = s.pageURL,
              !(findTab(s.tabID)?.isPrivate ?? false) else { return }
        let key = url.absoluteString + "|" + s.title
        let now = Date()
        let started = s.isPlaying && key != lastPersistKey
        let periodic = s.isPlaying && now.timeIntervalSince(lastPersistAt) > 15
        let stopped = wasPlaying && !s.isPlaying
        guard started || periodic || stopped else { return }
        lastPersistKey = key
        lastPersistAt = now
        library.recordMedia(title: s.title, artist: s.artist, host: s.host,
                            pageURL: url.absoluteString, artworkURL: s.artworkURL?.absoluteString,
                            duration: s.duration, position: s.position)
    }

    // MARK: - System notifications

    private func observeSystemNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appWillResignActive() }
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appDidBecomeActive() }
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appDidEnterBackground() }
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appWillEnterForeground() }
        }
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw) }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            Task { @MainActor in self?.handleRouteChange(reasonRaw: reasonRaw) }
        }
    }

    /// Picture in Picture: start it automatically when the user leaves the app during video playback.
    private func appWillResignActive() {
        guard Prefs.autoPiP, pipSupported, let s = session, s.isPlaying, s.isVideo, !s.pipActive else { return }
        autoPiPStarted = true
        send("pipOn")
    }

    private func appDidBecomeActive() {
        if autoPiPStarted {
            autoPiPStarted = false
            if session?.pipActive == true { send("pipOff") }
        }
    }

    private func appDidEnterBackground() {
        broadcastBackground(true)
        guard let s = session else { return }

        if !Prefs.backgroundPlayback {
            // User opted out: pause unless the video is floating in Picture in Picture.
            if !s.pipActive { pause() }
            return
        }
        if s.isPlaying {
            activateAudioSession()
            if Prefs.keepAlive { keepAlive.start() }
            beginBackgroundTask()
        }
    }

    private func appWillEnterForeground() {
        broadcastBackground(false)
        endBackgroundTask()
    }

    /// Tells every tab (and, through postMessage, every iframe) that the app is backgrounded.
    private func broadcastBackground(_ flag: Bool) {
        for tab in allTabs() {
            tab.runKV("setBg(\(flag))")
        }
        if let s = session, let frame = activeFrame {
            findTab(s.tabID)?.runKV("setBg(\(flag))", frame: frame)
        }
    }

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "KingVidPlaybackHandoff") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
        // The audio background mode keeps us alive; this only bridges the transition.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func handleInterruption(typeRaw: UInt, optionsRaw: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeRaw), session != nil else { return }
        switch type {
        case .began:
            send("interrupt")
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume), Prefs.resumeAfterInterruption {
                activateAudioSession()
                play()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonRaw: UInt) {
        // Headphones unplugged / Bluetooth disconnected: pause, like every media app.
        if AVAudioSession.RouteChangeReason(rawValue: reasonRaw) == .oldDeviceUnavailable, session?.isPlaying == true {
            pause()
        }
    }
}

/// Fallback Now Playing artwork: the KingVid crown on black (rendered once per accent colour).
@MainActor
enum CrownArtwork {
    private static var cache: [String: UIImage] = [:]

    static var image: UIImage {
        let key = Theme.accent.crownAsset
        if let cached = cache[key] { return cached }
        let size = CGSize(width: 600, height: 600)
        let rendered = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(Color(hex: 0x0B0B0C)).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let crown = UIImage(named: key) {
                let side: CGFloat = 340
                crown.draw(in: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side))
            }
        }
        cache[key] = rendered
        return rendered
    }
}
