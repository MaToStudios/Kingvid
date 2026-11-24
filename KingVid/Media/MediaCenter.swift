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

/// Central coordinator for media playback: owns the audio session, Now Playing info,
/// Lock Screen / Control Center commands, interruption + background handling and PiP triggers.
///
/// Playback itself always stays in the website's original player; this class only observes it
/// (via the `kvMedia` script messages) and controls it (via `window.__kv.cmd`).
@MainActor
final class MediaCenter: ObservableObject {
    @Published private(set) var session: MediaSession?
    @Published private(set) var artwork: UIImage?
    let pipSupported = AVPictureInPictureController.isPictureInPictureSupported()

    weak var browser: BrowserStore?
    private let library: LibraryStore

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

    // MARK: - Incoming state from pages

    func handle(_ body: [String: Any], from tab: BrowserTab, frame: WKFrameInfo) {
        guard (body["type"] as? String) == "state" else { return }

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
            browser?.tab(withID: previous.tabID)?.runKV("cmd('pause')")
        }
        if previous?.tabID != tab.id { browser?.mediaTabID = tab.id }
        activeFrame = frame

        if previous != updated { session = updated }
        loadArtwork(updated.artworkURL)
        playbackStateChanged(wasPlaying: previous?.isPlaying ?? false, session: updated)
        updateNowPlaying()
        persistRecent(updated, wasPlaying: previous?.isPlaying ?? false)
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
        browser?.tab(withID: current.tabID)?.runKV("cmd('pause')", frame: activeFrame)
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
        browser?.mediaTabID = nil
        keepAlive.stop()
        keepAliveStopTask?.cancel()
        updateNowPlaying()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func send(_ command: String, _ argument: Double? = nil) {
        guard let current = session, let tab = browser?.tab(withID: current.tabID) else { return }
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
              !(browser?.tab(withID: s.tabID)?.isPrivate ?? false) else { return }
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
        for tab in browser?.tabs ?? [] {
            tab.runKV("setBg(\(flag))")
        }
        if let s = session, let frame = activeFrame {
            browser?.tab(withID: s.tabID)?.runKV("setBg(\(flag))", frame: frame)
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

/// Fallback Now Playing artwork: the KingVid crown on black.
@MainActor
enum CrownArtwork {
    static let image: UIImage = {
        let view = ZStack {
            Color(hex: 0x0B0B0C)
            CrownLogo().padding(120)
        }
        .frame(width: 600, height: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage ?? UIImage()
    }()
}
