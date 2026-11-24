import Foundation
import SwiftData
import WebKit

struct BrowserSuggestion: Identifiable, Hashable {
    enum Kind { case favorite, bookmark, history }
    var id: String { urlString }
    let title: String
    let urlString: String
    let kind: Kind
}

/// Thin storage layer on top of SwiftData. All access happens on the main actor
/// through the container's main context, which is the same context SwiftUI's
/// `@Query` uses, so lists update automatically.
@MainActor
final class LibraryStore: ObservableObject {
    private let context: ModelContext
    /// Bumped on every mutation so menus/buttons that call `isBookmarked` etc. refresh.
    @Published private(set) var revision = 0

    init(context: ModelContext) {
        self.context = context
    }

    private func save() {
        try? context.save()
        revision += 1
    }

    // MARK: History

    func recordVisit(title: String, url: URL) {
        guard Prefs.saveHistory else { return }
        let key = url.absoluteString
        var latest = FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.visitedAt, order: .reverse)])
        latest.fetchLimit = 1
        if let last = try? context.fetch(latest).first,
           last.urlString == key,
           Date().timeIntervalSince(last.visitedAt) < 1800 {
            if !title.isEmpty { last.title = title }
            last.visitedAt = Date()
        } else {
            let shownTitle = title.isEmpty ? (url.host ?? key) : title
            context.insert(HistoryEntry(title: shownTitle, urlString: key))
        }
        save()
    }

    func clearHistory() {
        try? context.delete(model: HistoryEntry.self)
        save()
    }

    func delete(_ entry: HistoryEntry) {
        context.delete(entry)
        save()
    }

    // MARK: Bookmarks

    func bookmark(for url: URL) -> Bookmark? {
        let key = url.absoluteString
        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.urlString == key })
        return try? context.fetch(descriptor).first
    }

    func isBookmarked(_ url: URL) -> Bool { bookmark(for: url) != nil }

    func toggleBookmark(title: String, url: URL) {
        if let existing = bookmark(for: url) {
            context.delete(existing)
        } else {
            context.insert(Bookmark(title: title.isEmpty ? (url.host ?? url.absoluteString) : title,
                                    urlString: url.absoluteString))
        }
        save()
    }

    func delete(_ bookmark: Bookmark) {
        context.delete(bookmark)
        save()
    }

    // MARK: Favorites

    func favorite(for url: URL) -> FavoriteSite? {
        let key = url.absoluteString
        let descriptor = FetchDescriptor<FavoriteSite>(predicate: #Predicate { $0.urlString == key })
        return try? context.fetch(descriptor).first
    }

    func isFavorite(_ url: URL) -> Bool { favorite(for: url) != nil }

    func toggleFavorite(title: String, url: URL) {
        if let existing = favorite(for: url) {
            context.delete(existing)
        } else {
            addFavorite(title: title, urlString: url.absoluteString)
            return
        }
        save()
    }

    func addFavorite(title: String, urlString: String) {
        let count = (try? context.fetchCount(FetchDescriptor<FavoriteSite>())) ?? 0
        let host = URL(string: urlString)?.host ?? urlString
        context.insert(FavoriteSite(title: title.isEmpty ? host : title, urlString: urlString, sortIndex: count))
        save()
    }

    func delete(_ favorite: FavoriteSite) {
        context.delete(favorite)
        save()
    }

    // MARK: Recently played

    func recordMedia(title: String, artist: String, host: String, pageURL: String,
                     artworkURL: String?, duration: Double, position: Double) {
        let descriptor = FetchDescriptor<RecentMedia>(predicate: #Predicate { $0.pageURLString == pageURL })
        if let existing = try? context.fetch(descriptor).first {
            existing.title = title
            existing.artist = artist
            existing.artworkURLString = artworkURL ?? existing.artworkURLString
            existing.duration = duration
            existing.position = position
            existing.lastPlayedAt = Date()
        } else {
            context.insert(RecentMedia(title: title, artist: artist, host: host, pageURLString: pageURL,
                                       artworkURLString: artworkURL, duration: duration, position: position))
        }
        trimRecentMedia()
        save()
    }

    private func trimRecentMedia(limit: Int = 60) {
        var descriptor = FetchDescriptor<RecentMedia>(sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)])
        descriptor.fetchOffset = limit
        if let extra = try? context.fetch(descriptor) {
            for item in extra { context.delete(item) }
        }
    }

    func clearRecentMedia() {
        try? context.delete(model: RecentMedia.self)
        save()
    }

    // MARK: Address bar suggestions

    func suggestions(for query: String, limit: Int = 6) -> [BrowserSuggestion] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var results: [BrowserSuggestion] = []
        var seen = Set<String>()

        func add(_ title: String, _ url: String, _ kind: BrowserSuggestion.Kind) {
            guard results.count < limit, !seen.contains(url) else { return }
            if title.lowercased().contains(q) || url.lowercased().contains(q) {
                seen.insert(url)
                results.append(BrowserSuggestion(title: title, urlString: url, kind: kind))
            }
        }

        if let favorites = try? context.fetch(FetchDescriptor<FavoriteSite>(sortBy: [SortDescriptor(\.sortIndex)])) {
            for f in favorites { add(f.title, f.urlString, .favorite) }
        }
        if let bookmarks = try? context.fetch(FetchDescriptor<Bookmark>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])) {
            for b in bookmarks { add(b.title, b.urlString, .bookmark) }
        }
        var history = FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.visitedAt, order: .reverse)])
        history.fetchLimit = 400
        if let entries = try? context.fetch(history) {
            for e in entries { add(e.title, e.urlString, .history) }
        }
        return results
    }

    // MARK: Website data

    func clearWebsiteData() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
}
