import SwiftUI
import SwiftData

/// Composition root: owns the storage container and the browser, media and library services.
@MainActor
final class AppModel: ObservableObject {
    enum Sheet: String, Identifiable {
        case library, settings, tabs, player
        var id: String { rawValue }
    }

    let container: ModelContainer
    let library: LibraryStore
    let media: MediaCenter
    let browser: BrowserStore

    @Published var sheet: Sheet?

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
        media.browser = browser
        self.library = library
        self.media = media
        self.browser = browser
        browser.start()
    }

    /// Opens a URL from the library or start page in the current tab and returns to browsing.
    func open(_ url: URL) {
        browser.open(url)
        sheet = nil
    }
}
