import Foundation
import SwiftData

@Model
final class Bookmark {
    var title: String
    var urlString: String
    var createdAt: Date

    init(title: String, urlString: String, createdAt: Date = Date()) {
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
    }
}

@Model
final class FavoriteSite {
    var title: String
    var urlString: String
    var sortIndex: Int
    var createdAt: Date

    init(title: String, urlString: String, sortIndex: Int, createdAt: Date = Date()) {
        self.title = title
        self.urlString = urlString
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

@Model
final class HistoryEntry {
    var title: String
    var urlString: String
    var visitedAt: Date

    init(title: String, urlString: String, visitedAt: Date = Date()) {
        self.title = title
        self.urlString = urlString
        self.visitedAt = visitedAt
    }
}

@Model
final class RecentMedia {
    var title: String
    var artist: String
    var host: String
    var pageURLString: String
    var artworkURLString: String?
    var duration: Double
    var position: Double
    var lastPlayedAt: Date

    init(title: String, artist: String, host: String, pageURLString: String,
         artworkURLString: String?, duration: Double, position: Double,
         lastPlayedAt: Date = Date()) {
        self.title = title
        self.artist = artist
        self.host = host
        self.pageURLString = pageURLString
        self.artworkURLString = artworkURLString
        self.duration = duration
        self.position = position
        self.lastPlayedAt = lastPlayedAt
    }
}
