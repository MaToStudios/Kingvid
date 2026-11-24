import Foundation

enum SearchEngine: String, CaseIterable, Identifiable {
    case google, duckduckgo, bing, brave, yahoo, youtube

    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .brave: return "Brave Search"
        case .yahoo: return "Yahoo"
        case .youtube: return "YouTube"
        }
    }

    private var base: String {
        switch self {
        case .google: return "https://www.google.com/search"
        case .duckduckgo: return "https://duckduckgo.com/"
        case .bing: return "https://www.bing.com/search"
        case .brave: return "https://search.brave.com/search"
        case .yahoo: return "https://search.yahoo.com/search"
        case .youtube: return "https://m.youtube.com/results"
        }
    }

    private var queryName: String {
        switch self {
        case .yahoo: return "p"
        case .youtube: return "search_query"
        default: return "q"
        }
    }

    func searchURL(for query: String) -> URL? {
        var comps = URLComponents(string: base)
        comps?.queryItems = [URLQueryItem(name: queryName, value: query)]
        return comps?.url
    }

    static var current: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: SettingsKey.searchEngine) ?? "") ?? .google
    }
}

enum URLResolver {
    /// Turns whatever the user typed into a URL: a full URL, a bare host, or a web search.
    static func resolve(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased() {
            if ["http", "https"].contains(scheme), url.host != nil { return url }
            if ["file", "about", "data"].contains(scheme) { return url }
        }
        if !text.contains(" ") {
            let looksLikeHost = text.contains(".") || text.lowercased().hasPrefix("localhost")
            if looksLikeHost, let url = URL(string: "https://" + text), url.host != nil {
                return url
            }
        }
        return SearchEngine.current.searchURL(for: text)
    }
}

struct FeaturedSite: Identifiable {
    let name: String
    let urlString: String
    let symbol: String
    var id: String { urlString }

    static let all: [FeaturedSite] = [
        FeaturedSite(name: "YouTube", urlString: "https://m.youtube.com", symbol: "play.rectangle.fill"),
        FeaturedSite(name: "YT Music", urlString: "https://music.youtube.com", symbol: "music.note"),
        FeaturedSite(name: "Vimeo", urlString: "https://vimeo.com", symbol: "film.fill"),
        FeaturedSite(name: "Dailymotion", urlString: "https://www.dailymotion.com", symbol: "play.tv.fill"),
        FeaturedSite(name: "SoundCloud", urlString: "https://soundcloud.com", symbol: "waveform"),
        FeaturedSite(name: "Twitch", urlString: "https://www.twitch.tv", symbol: "dot.radiowaves.left.and.right"),
        FeaturedSite(name: "Bandcamp", urlString: "https://bandcamp.com", symbol: "opticaldisc.fill"),
        FeaturedSite(name: "Mixcloud", urlString: "https://www.mixcloud.com", symbol: "headphones"),
        FeaturedSite(name: "Archive", urlString: "https://archive.org/details/movies", symbol: "building.columns.fill"),
        FeaturedSite(name: "Google", urlString: "https://www.google.com", symbol: "magnifyingglass"),
        FeaturedSite(name: "Wikipedia", urlString: "https://en.m.wikipedia.org", symbol: "book.closed.fill"),
        FeaturedSite(name: "Reddit", urlString: "https://www.reddit.com", symbol: "bubble.left.and.bubble.right.fill")
    ]
}
