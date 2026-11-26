import Foundation

/// Loads YouTube's own mobile pages and reads the data they embed (via `YouTubeParser`).
/// Used for the native home/search feeds and as a fallback for watch-screen details.
/// Playback itself always stays in the real YouTube player inside the web view.
enum YouTubeService {
    enum ServiceError: LocalizedError {
        case noData
        var errorDescription: String? { "YouTube didn't return any videos. Check your connection and try again." }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static var userAgent: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(v.majorVersion)_\(v.minorVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(v.majorVersion).\(v.minorVersion) Mobile/15E148 Safari/604.1"
    }

    private static func fetchHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let languages = Locale.preferredLanguages.prefix(3).joined(separator: ",")
        request.setValue(languages.isEmpty ? "en-US,en" : languages, forHTTPHeaderField: "Accept-Language")
        // Skips the EU cookie-consent interstitial for these anonymous data requests.
        request.setValue("SOCS=CAI; CONSENT=YES+cb", forHTTPHeaderField: "Cookie")
        let (data, _) = try await session.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }

    /// Videos for a search query (first page of results).
    static func search(_ query: String) async throws -> [YTVideo] {
        var comps = URLComponents(string: "https://m.youtube.com/results")!
        comps.queryItems = [URLQueryItem(name: "search_query", value: query)]
        let html = try await fetchHTML(comps.url!)
        let json = YouTubeParser.initialJSON(named: "ytInitialData", in: html)
        let videos = YouTubeParser.videos(in: json)
        if videos.isEmpty {
            let size = html.count
            await MainActor.run { DiagnosticsLog.shared.add("youtube", "search '\(query)' returned no parsable videos (\(size) bytes)") }
            throw ServiceError.noData
        }
        return videos
    }

    /// Title, channel, description and related videos for one video.
    static func watchInfo(_ videoID: String) async -> YTWatchInfo? {
        guard let url = URL(string: "https://m.youtube.com/watch?v=\(videoID)"),
              let html = try? await fetchHTML(url) else { return nil }
        let player = YouTubeParser.initialJSON(named: "ytInitialPlayerResponse", in: html)
        let data = YouTubeParser.initialJSON(named: "ytInitialData", in: html)
        return YouTubeParser.watchInfo(playerResponse: player, initialData: data)
    }
}
