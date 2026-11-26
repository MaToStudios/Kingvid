import SwiftUI
import WebKit

/// Home feed categories. Each is a real YouTube search, so the feed works without signing in
/// (YouTube's own home page is empty for signed-out users).
enum YTCategory: String, CaseIterable, Identifiable {
    case discover, music, gaming, news, live, podcasts, sports, learning, comedy, trailers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: return "Discover"
        case .music: return "Music"
        case .gaming: return "Gaming"
        case .news: return "News"
        case .live: return "Live"
        case .podcasts: return "Podcasts"
        case .sports: return "Sports"
        case .learning: return "Learning"
        case .comedy: return "Comedy"
        case .trailers: return "Trailers"
        }
    }

    func query(recent: [String]) -> String {
        switch self {
        case .discover: return recent.first ?? "trending videos"
        case .music: return "new music videos"
        case .gaming: return "gaming"
        case .news: return "news today"
        case .live: return "live now"
        case .podcasts: return "podcast full episode"
        case .sports: return "sports highlights"
        case .learning: return "documentary"
        case .comedy: return "stand up comedy"
        case .trailers: return "official trailer"
        }
    }
}

/// Controller for the YouTube experience.
///
/// * Home / search results: native, thumbnail-first feed built from YouTube's own page data.
/// * Web mode: the real m.youtube.com for account pages (subscriptions, library, playlists, channels, sign-in).
/// * Player: a dedicated web view running the original YouTube player, shown video-only inside the native
///   watch screen. It keeps playing (mini-player, background audio, PiP) while you browse.
@MainActor
final class YouTubeExperience: ObservableObject {
    enum Mode: Equatable {
        case home
        case results(String)
        case web
    }

    enum FeedState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    @Published var mode: Mode = .home
    @Published private(set) var category: YTCategory = .discover
    @Published private(set) var feed: [YTVideo] = []
    @Published private(set) var feedState: FeedState = .idle

    @Published private(set) var browse: BrowserTab?
    @Published private(set) var player: BrowserTab?
    /// The full-screen watch screen is showing (false = minimised to the mini-player).
    @Published var isWatching = false
    @Published var showSearch = false
    @Published private(set) var recentSearches: [String]

    @Published private(set) var currentVideoID: String?
    @Published private(set) var watchInfo: YTWatchInfo?

    /// Set by `AppModel`: open a non-YouTube link in the Browser section.
    var onOpenExternal: ((URL) -> Void)?

    private let store: BrowserStore
    private var feedTask: Task<Void, Never>?
    private var infoTask: Task<Void, Never>?
    private var feedCache: [String: [YTVideo]] = [:]

    init(store: BrowserStore) {
        self.store = store
        self.recentSearches = UserDefaults.standard.stringArray(forKey: SettingsKey.ytRecentSearches) ?? []
    }

    var tabs: [BrowserTab] { [browse, player].compactMap { $0 } }

    /// Called when the YouTube section is first opened.
    func ensureStarted() {
        if feed.isEmpty, feedState != .loading { loadFeed() }
    }

    // MARK: Native feed

    private var feedQuery: String {
        if case .results(let q) = mode { return q }
        return category.query(recent: recentSearches)
    }

    func loadFeed(force: Bool = false) {
        let query = feedQuery
        if !force, let cached = feedCache[query] {
            feed = cached
            feedState = .loaded
            return
        }
        feedTask?.cancel()
        feedState = .loading
        feedTask = Task { [weak self] in
            do {
                let videos = try await YouTubeService.search(query)
                guard !Task.isCancelled, let self, self.feedQuery == query else { return }
                self.feedCache[query] = videos
                self.feed = videos
                self.feedState = .loaded
            } catch {
                guard !Task.isCancelled, let self, self.feedQuery == query else { return }
                self.feedState = .failed(error.localizedDescription)
            }
        }
    }

    func select(_ category: YTCategory) {
        self.category = category
        mode = .home
        loadFeed()
    }

    func showHome() {
        mode = .home
        loadFeed()
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        recentSearches = Array(updated.prefix(12))
        UserDefaults.standard.set(recentSearches, forKey: SettingsKey.ytRecentSearches)
        showSearch = false
        isWatching = false
        mode = .results(trimmed)
        loadFeed()
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: SettingsKey.ytRecentSearches)
    }

    // MARK: Web mode (account pages, channels, playlists)

    private func ensureBrowse() -> BrowserTab {
        if let browse { return browse }
        let tab = BrowserTab(url: nil, isPrivate: false, kind: .youtubeBrowse, store: store)
        tab.onWatchRequest = { [weak self] url in self?.play(url) }
        tab.onOpenExternal = { [weak self] url in self?.onOpenExternal?(url) }
        tab.onURLChange = { [weak self] url in self?.browseURLChanged(url) }
        browse = tab
        return tab
    }

    /// Safety net for videos that slip past the click interception (client-side routing, redirects).
    private func browseURLChanged(_ url: URL?) {
        guard let url, YouTubeURL.isWatch(url), let browse else { return }
        DiagnosticsLog.shared.add("youtube", "browse view reached a watch URL; redirecting to player")
        browse.runKV("cmd('pause')")
        if browse.canGoBack { browse.goBack() } else { mode = .home }
        play(url)
    }

    func open(route: YouTubeRoute) {
        if route == .home {
            isWatching = false
            showHome()
            return
        }
        browseTo(route.url)
    }

    func browseTo(_ url: URL) {
        let tab = ensureBrowse()
        isWatching = false
        mode = .web
        tab.load(url)
    }

    func openChannel(_ path: String) {
        guard let url = URL(string: "https://m.youtube.com" + (path.hasPrefix("/") ? path : "/" + path)) else { return }
        browseTo(url)
    }

    func signIn() { browseTo(YouTubeURL.signInURL) }

    // MARK: Player

    func play(_ url: URL) {
        let target = YouTubeURL.canonicalWatch(url)
        let id = YouTubeURL.videoID(target)

        let tab: BrowserTab
        if let existing = player {
            tab = existing
        } else {
            tab = BrowserTab(url: nil, isPrivate: false, kind: .youtubePlayer, store: store)
            tab.onWatchRequest = { [weak self] next in self?.play(next) }
            tab.onOpenExternal = { [weak self] next in self?.onOpenExternal?(next) }
            tab.onWatchData = { [weak self] body in self?.handleWatchData(body) }
            tab.onURLChange = { [weak self] url in self?.playerURLChanged(url) }
            player = tab
        }

        // Re-opening the same video just brings the watch screen back; it keeps playing where it was.
        if id == nil || id != currentVideoID || tab.url == nil {
            DiagnosticsLog.shared.add("youtube", "loading \(target.absoluteString)")
            videoChanged(to: id)
            tab.load(target)
        }
        showSearch = false
        isWatching = true
    }

    func minimize() { isWatching = false }

    /// Stops playback and discards the player view.
    func closePlayer() {
        guard let tab = player else { return }
        store.media.tabClosed(tab.id)
        tab.teardown()
        player = nil
        currentVideoID = nil
        watchInfo = nil
        infoTask?.cancel()
        isWatching = false
    }

    // MARK: Watch details

    private func videoChanged(to id: String?) {
        currentVideoID = id
        if watchInfo?.videoID != id { watchInfo = nil }
        infoTask?.cancel()
        guard let id else { return }
        // The page normally posts its own data within a second; fetch it ourselves if it doesn't
        // (e.g. after YouTube autoplays the next video inside the page).
        infoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self, self.watchInfo?.videoID != id else { return }
            let info = await YouTubeService.watchInfo(id)
            guard !Task.isCancelled, self.currentVideoID == id, let info else { return }
            self.watchInfo = info
        }
    }

    private func playerURLChanged(_ url: URL?) {
        guard let url, let id = YouTubeURL.videoID(url), id != currentVideoID else { return }
        videoChanged(to: id)
    }

    private func handleWatchData(_ body: [String: Any]) {
        guard let id = body["videoId"] as? String, id == currentVideoID else { return }
        let playerJSON = body["playerResponse"] as? String ?? ""
        let initialJSON = body["initialData"] as? String ?? ""
        Task { [weak self] in
            let info = await Task.detached(priority: .userInitiated) { () -> YTWatchInfo? in
                let pr = try? JSONSerialization.jsonObject(with: Data(playerJSON.utf8))
                let data = try? JSONSerialization.jsonObject(with: Data(initialJSON.utf8))
                return YouTubeParser.watchInfo(playerResponse: pr, initialData: data)
            }.value
            guard let self, let info, self.currentVideoID == id else { return }
            self.infoTask?.cancel()
            self.watchInfo = info
        }
    }
}

/// Rotates the app for the watch screen's fullscreen button (works with rotation lock on).
enum OrientationController {
    @MainActor
    static func set(landscape: Bool) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
