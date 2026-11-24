import Foundation

/// URL helpers for the YouTube experience. Pure functions, easy to reason about.
enum YouTubeURL {
    static func isYouTubeHost(_ host: String) -> Bool {
        host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    /// youtube.com pages that belong in the YouTube experience (music.youtube.com is a separate app: Browser tab).
    static func isYouTube(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), host != "music.youtube.com" else { return false }
        return isYouTubeHost(host)
    }

    /// Hosts the YouTube browse view is allowed to stay on (YouTube itself, Google sign-in/consent, CDNs).
    static func isInternalHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        let suffixes = ["youtube.com", "youtu.be", "google.com", "gstatic.com", "googleusercontent.com",
                        "ytimg.com", "googlevideo.com", "youtube-nocookie.com", "googleapis.com", "ggpht.com"]
        return suffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func isWatch(_ url: URL) -> Bool {
        guard isYouTube(url), let host = url.host?.lowercased() else { return false }
        if host == "youtu.be" { return url.path.count > 1 }
        let path = url.path
        return path == "/watch" || path.hasPrefix("/shorts/") || path.hasPrefix("/live/")
    }

    /// Normalises any watch URL (youtu.be, www, shorts, live) to the mobile site the web view uses.
    static func canonicalWatch(_ url: URL) -> URL {
        guard let host = url.host?.lowercased() else { return url }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "m.youtube.com"
        if host == "youtu.be" {
            let id = String(url.path.dropFirst())
            comps.path = "/watch"
            var items = [URLQueryItem(name: "v", value: id)]
            items += (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).filter { $0.name == "t" || $0.name == "list" }
            comps.queryItems = items
        } else {
            comps.path = url.path
            comps.percentEncodedQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        }
        return comps.url ?? url
    }

    static func videoID(_ url: URL) -> String? {
        guard isWatch(url) else { return nil }
        let host = url.host?.lowercased() ?? ""
        if host == "youtu.be" { return String(url.path.dropFirst()) }
        if url.path.hasPrefix("/shorts/") || url.path.hasPrefix("/live/") {
            return url.path.split(separator: "/").dropFirst().first.map(String.init)
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
    }

    static func searchURL(_ query: String) -> URL? {
        var comps = URLComponents(string: "https://m.youtube.com/results")
        comps?.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return comps?.url
    }

    static let signInURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&continue=https%3A%2F%2Fm.youtube.com%2Ffeed%2Flibrary")!
}

/// The sections shown as chips under the YouTube top bar. Each is a real YouTube route.
enum YouTubeRoute: String, CaseIterable, Identifiable {
    case home, subscriptions, library, history, watchLater, liked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .subscriptions: return "Subscriptions"
        case .library: return "Library"
        case .history: return "History"
        case .watchLater: return "Watch Later"
        case .liked: return "Liked"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .subscriptions: return "play.square.stack.fill"
        case .library: return "books.vertical.fill"
        case .history: return "clock.fill"
        case .watchLater: return "clock.badge.checkmark.fill"
        case .liked: return "hand.thumbsup.fill"
        }
    }

    var url: URL {
        switch self {
        case .home: return URL(string: "https://m.youtube.com/")!
        case .subscriptions: return URL(string: "https://m.youtube.com/feed/subscriptions")!
        case .library: return URL(string: "https://m.youtube.com/feed/library")!
        case .history: return URL(string: "https://m.youtube.com/feed/history")!
        case .watchLater: return URL(string: "https://m.youtube.com/playlist?list=WL")!
        case .liked: return URL(string: "https://m.youtube.com/playlist?list=LL")!
        }
    }

    static func match(_ url: URL?) -> YouTubeRoute? {
        guard let url, YouTubeURL.isYouTube(url) else { return nil }
        let path = url.path
        let list = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "list" }?.value
        if path == "/" || path.isEmpty { return .home }
        if path.hasPrefix("/feed/subscriptions") { return .subscriptions }
        if path.hasPrefix("/feed/library") || path.hasPrefix("/feed/you") { return .library }
        if path.hasPrefix("/feed/history") { return .history }
        if path == "/playlist", list == "WL" { return .watchLater }
        if path == "/playlist", list == "LL" { return .liked }
        return nil
    }
}
