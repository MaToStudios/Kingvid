import SwiftUI
import WebKit

/// Controller for the dedicated YouTube experience.
///
/// Two long-lived web views, both showing the real m.youtube.com (original YouTube player, accounts,
/// playlists and search all keep working):
///   * `browse`  – home, search results, channels, library. Taps on videos are intercepted.
///   * `player`  – the watch page. It keeps playing (mini-player, background audio, PiP) while you
///                 go back to browsing in the other view.
@MainActor
final class YouTubeExperience: ObservableObject {
    @Published private(set) var browse: BrowserTab?
    @Published private(set) var player: BrowserTab?
    /// The full-screen watch screen is showing (false = minimised to the mini-player).
    @Published var isWatching = false
    @Published var showSearch = false
    @Published private(set) var recentSearches: [String]

    /// Set by `AppModel`: open a non-YouTube link in the Browser section.
    var onOpenExternal: ((URL) -> Void)?

    private let store: BrowserStore
    private var currentVideoID: String?

    init(store: BrowserStore) {
        self.store = store
        self.recentSearches = UserDefaults.standard.stringArray(forKey: SettingsKey.ytRecentSearches) ?? []
    }

    var tabs: [BrowserTab] { [browse, player].compactMap { $0 } }

    // MARK: Browse view

    /// Creates the browse web view the first time the YouTube section is opened.
    func ensureStarted() {
        guard browse == nil else { return }
        let tab = BrowserTab(url: YouTubeRoute.home.url, isPrivate: false, kind: .youtubeBrowse, store: store)
        tab.onWatchRequest = { [weak self] url in self?.play(url) }
        tab.onOpenExternal = { [weak self] url in self?.onOpenExternal?(url) }
        tab.onURLChange = { [weak self] url in self?.browseURLChanged(url) }
        browse = tab
        tab.ensureLoaded()
    }

    /// Safety net for videos that slip past the click interception (client-side routing, redirects).
    private func browseURLChanged(_ url: URL?) {
        guard let url, YouTubeURL.isWatch(url), let browse else { return }
        DiagnosticsLog.shared.add("youtube", "browse view reached a watch URL; redirecting to player")
        browse.runKV("cmd('pause')")
        if browse.canGoBack { browse.goBack() } else { browse.load(YouTubeRoute.home.url) }
        play(url)
    }

    func open(route: YouTubeRoute) {
        ensureStarted()
        isWatching = false
        browse?.load(route.url)
    }

    func browseTo(_ url: URL) {
        ensureStarted()
        isWatching = false
        browse?.load(url)
    }

    func signIn() {
        ensureStarted()
        isWatching = false
        browse?.load(YouTubeURL.signInURL)
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = YouTubeURL.searchURL(trimmed) else { return }
        ensureStarted()
        var updated = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        recentSearches = Array(updated.prefix(12))
        UserDefaults.standard.set(recentSearches, forKey: SettingsKey.ytRecentSearches)
        showSearch = false
        isWatching = false
        browse?.load(url)
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: SettingsKey.ytRecentSearches)
    }

    // MARK: Player view

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
            player = tab
        }

        // Re-opening the same video just brings the watch screen back; it keeps playing where it was.
        if id == nil || id != currentVideoID || tab.url == nil {
            currentVideoID = id
            DiagnosticsLog.shared.add("youtube", "loading \(target.absoluteString)")
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
        isWatching = false
    }
}
