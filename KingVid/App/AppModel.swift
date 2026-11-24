import SwiftUI
import SwiftData

enum AppSection: String, CaseIterable, Identifiable {
    case home, youtube, browser, library, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .youtube: return "YouTube"
        case .browser: return "Browser"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .youtube: return "play.rectangle.fill"
        case .browser: return "safari.fill"
        case .library: return "books.vertical.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Composition root: owns the storage container and the browser, media, YouTube and library services.
@MainActor
final class AppModel: ObservableObject {
    enum Sheet: String, Identifiable {
        case tabs, player
        var id: String { rawValue }
    }

    let container: ModelContainer
    let library: LibraryStore
    let media: MediaCenter
    let browser: BrowserStore
    let youtube: YouTubeExperience

    @Published var sheet: Sheet?
    @Published var section: AppSection = .home {
        didSet {
            visited.insert(section)
            if section == .youtube { youtube.ensureStarted() }
        }
    }
    /// Sections that have been opened at least once (heavy ones are created lazily and then kept alive).
    @Published private(set) var visited: Set<AppSection> = [.home, .browser]

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Bookmark.self, FavoriteSite.self, HistoryEntry.self, RecentMedia.self)
        } catch {
            // Fall back to memory so a corrupt store never prevents the app from launching.
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: Bookmark.self, FavoriteSite.self,
                                            HistoryEntry.self, RecentMedia.self,
                                            configurations: memory)
        }
        self.container = container
        let library = LibraryStore(context: container.mainContext)
        let media = MediaCenter(library: library)
        let browser = BrowserStore(media: media, library: library)
        let youtube = YouTubeExperience(store: browser)

        self.library = library
        self.media = media
        self.browser = browser
        self.youtube = youtube

        media.allTabs = { [weak browser, weak youtube] in
            (browser?.tabs ?? []) + (youtube?.tabs ?? [])
        }
        browser.extraTabs = { [weak youtube] in youtube?.tabs ?? [] }
        youtube.onOpenExternal = { [weak self] url in self?.showInBrowser(url) }
        browser.start()
    }

    // MARK: Routing

    /// Opens a URL from anywhere (library, home, recents) in the right place: YouTube links in the
    /// YouTube experience, everything else in the Browser.
    func open(_ url: URL) {
        sheet = nil
        if YouTubeURL.isWatch(url) {
            youtube.play(url)
            if section != .youtube { section = .youtube }
        } else if YouTubeURL.isYouTube(url) {
            section = .youtube
            youtube.browseTo(url)
        } else {
            showInBrowser(url)
        }
    }

    func showInBrowser(_ url: URL) {
        sheet = nil
        section = .browser
        browser.open(url)
    }

    /// Mini-player tap: YouTube videos reopen the watch screen, everything else opens the player sheet.
    func expandPlayer() {
        guard let session = media.session else { return }
        if session.tabID == youtube.player?.id {
            youtube.isWatching = true
        } else {
            sheet = .player
        }
    }

    /// True while the full-screen YouTube watch screen is covering the app.
    var isImmersive: Bool { youtube.isWatching }
}
