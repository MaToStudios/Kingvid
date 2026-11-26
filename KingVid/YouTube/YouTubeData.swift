import Foundation

/// One video (or Short) as listed in YouTube's own page data.
struct YTVideo: Identifiable, Hashable {
    let id: String
    let title: String
    let channel: String
    /// Channel path as YouTube links it, e.g. "/@LofiGirl" or "/channel/UC...".
    let channelPath: String?
    let avatarURL: URL?
    let views: String
    let published: String
    let duration: String
    let isLive: Bool
    let isShort: Bool
    let thumbnail: URL?

    /// Best thumbnail YouTube listed for this item (16:9 `hq720` for videos, 9:16 for Shorts);
    /// `fallbackThumbnail` always exists.
    var largeThumbnail: URL? {
        thumbnail ?? fallbackThumbnail
    }
    var fallbackThumbnail: URL? {
        isShort ? URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg") : URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
    }

    var watchURL: URL {
        URL(string: isShort ? "https://m.youtube.com/shorts/\(id)" : "https://m.youtube.com/watch?v=\(id)")!
    }

    /// "Channel · 1.2M views · 3 days ago"
    var metaLine: String {
        [channel, views, published].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Everything the watch screen shows below the video.
struct YTWatchInfo: Equatable {
    let videoID: String
    var title: String
    var channel: String
    var channelPath: String?
    var avatarURL: URL?
    var views: String
    var published: String
    var description: String
    var isLive: Bool
    var related: [YTVideo]
}

/// Parses the JSON YouTube embeds in its own pages (`ytInitialData`, `ytInitialPlayerResponse`).
/// Pure Foundation so it is unit-tested on real page data (see tools/test_youtube_parser.sh).
enum YouTubeParser {

    // MARK: Locating the embedded JSON

    /// Finds `var NAME = …;` / `window["NAME"] = …;` in an HTML page. YouTube embeds it either as a JSON
    /// object literal or as a JavaScript string literal with `\xNN` escapes; both are handled.
    static func initialJSON(named name: String, in html: String) -> Any? {
        let markers = ["var \(name) = ", "window[\"\(name)\"] = ", "\(name) = "]
        for marker in markers {
            guard let range = html.range(of: marker) else { continue }
            let scalars = html.unicodeScalars
            var i = range.upperBound.samePosition(in: scalars) ?? scalars.startIndex
            while i < scalars.endIndex, scalars[i] == " " { i = scalars.index(after: i) }
            guard i < scalars.endIndex else { continue }
            let jsonText: String?
            if scalars[i] == "'" {
                jsonText = jsStringLiteral(scalars, from: scalars.index(after: i))
            } else if scalars[i] == "{" {
                jsonText = jsonObjectLiteral(scalars, from: i)
            } else {
                jsonText = nil
            }
            if let jsonText, let data = jsonText.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                return object
            }
        }
        return nil
    }

    /// Decodes a single-quoted JS string literal starting just after the opening quote.
    private static func jsStringLiteral(_ s: String.UnicodeScalarView, from start: String.UnicodeScalarView.Index) -> String? {
        let chars = Array(s[start...])
        var units: [UInt16] = []
        units.reserveCapacity(chars.count)

        func hexValue(at index: Int, digits: Int) -> UInt16? {
            guard index + digits <= chars.count else { return nil }
            var v: UInt16 = 0
            for k in index..<(index + digits) {
                guard let d = Character(chars[k]).hexDigitValue else { return nil }
                v = v * 16 + UInt16(d)
            }
            return v
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "'" { return String(decoding: units, as: UTF16.self) }
            if c == "\\", i + 1 < chars.count {
                let e = chars[i + 1]
                switch e {
                case "x":
                    guard let v = hexValue(at: i + 2, digits: 2) else { return nil }
                    units.append(v); i += 4; continue
                case "u":
                    guard let v = hexValue(at: i + 2, digits: 4) else { return nil }
                    units.append(v); i += 6; continue
                case "n": units.append(10)
                case "t": units.append(9)
                case "r": units.append(13)
                case "b": units.append(8)
                case "f": units.append(12)
                case "v": units.append(11)
                case "0": units.append(0)
                default: units.append(contentsOf: String(e).utf16)
                }
                i += 2
                continue
            }
            units.append(contentsOf: String(c).utf16)
            i += 1
        }
        return nil
    }

    /// Returns the `{ … }` JSON object starting at `start` (string-aware brace matching).
    private static func jsonObjectLiteral(_ s: String.UnicodeScalarView, from start: String.UnicodeScalarView.Index) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < s.endIndex {
            let c = s[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else {
                if c == "\"" { inString = true }
                else if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return String(s[start...i]) }
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    // MARK: Small JSON helpers

    /// Text from YouTube's text containers: `{runs:[{text}]}`, `{simpleText}`, `{content}` or a plain string.
    static func text(_ any: Any?) -> String {
        if let s = any as? String { return s }
        guard let d = any as? [String: Any] else { return "" }
        if let s = d["simpleText"] as? String { return s }
        if let s = d["content"] as? String { return s }
        if let runs = d["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    private static func dict(_ any: Any?, _ path: String...) -> [String: Any]? {
        var current = any
        for key in path { current = (current as? [String: Any])?[key] }
        return current as? [String: Any]
    }

    private static func value(_ any: Any?, _ path: [String]) -> Any? {
        var current = any
        for key in path { current = (current as? [String: Any])?[key] }
        return current
    }

    /// Largest thumbnail URL from `{thumbnails:[{url,width}]}` or `{sources:[{url,width}]}`.
    private static func bestImage(_ any: Any?) -> URL? {
        guard let d = any as? [String: Any] else { return nil }
        let list = (d["thumbnails"] as? [[String: Any]]) ?? (d["sources"] as? [[String: Any]]) ?? []
        let best = list.max { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
        guard var url = best?["url"] as? String else { return nil }
        if url.hasPrefix("//") { url = "https:" + url }
        return URL(string: url)
    }

    // MARK: Video lists

    private static let standardKeys = ["videoWithContextRenderer", "compactVideoRenderer", "videoRenderer", "gridVideoRenderer"]

    /// All videos and Shorts in a page's data, in page order, de-duplicated.
    static func videos(in json: Any?) -> [YTVideo] {
        var result: [YTVideo] = []
        var seen = Set<String>()
        func add(_ v: YTVideo?) {
            guard let v, !v.id.isEmpty, !v.title.isEmpty, seen.insert(v.id).inserted else { return }
            result.append(v)
        }
        func walk(_ any: Any?, depth: Int) {
            guard depth < 80 else { return }
            if let d = any as? [String: Any] {
                for (key, child) in d {
                    if standardKeys.contains(key) {
                        add(standardVideo(child as? [String: Any]))
                    } else if key == "shortsLockupViewModel" {
                        add(shortVideo(child as? [String: Any]))
                    } else if key == "reelItemRenderer" {
                        add(reelVideo(child as? [String: Any]))
                    } else if key == "lockupViewModel" {
                        add(lockupVideo(child as? [String: Any]))
                    } else {
                        walk(child, depth: depth + 1)
                    }
                }
            } else if let a = any as? [Any] {
                for child in a { walk(child, depth: depth + 1) }
            }
        }
        walk(json, depth: 0)
        return result
    }

    private static func standardVideo(_ d: [String: Any]?) -> YTVideo? {
        guard let d, let id = d["videoId"] as? String else { return nil }
        let byline = d["shortBylineText"] ?? d["longBylineText"] ?? d["ownerText"]
        let firstRun = ((byline as? [String: Any])?["runs"] as? [[String: Any]])?.first
        let endpoint = firstRun?["navigationEndpoint"] as? [String: Any]
        let channelPath = (value(endpoint, ["browseEndpoint", "canonicalBaseUrl"]) as? String)
            ?? (value(endpoint, ["commandMetadata", "webCommandMetadata", "url"]) as? String)

        var duration = text(d["lengthText"])
        var isLive = false
        for overlay in (d["thumbnailOverlays"] as? [[String: Any]]) ?? [] {
            if let status = overlay["thumbnailOverlayTimeStatusRenderer"] as? [String: Any] {
                let style = status["style"] as? String ?? ""
                if style == "LIVE" { isLive = true }
                else if duration.isEmpty { duration = text(status["text"]) }
            }
        }
        let views = text(d["shortViewCountText"]).isEmpty ? text(d["viewCountText"]) : text(d["shortViewCountText"])
        if views.contains("watching") { isLive = true }
        let avatar = bestImage(dict(d["channelThumbnail"], "channelThumbnailWithLinkRenderer", "thumbnail"))
            ?? bestImage(dict(d["channelThumbnail"]))
            ?? bestImage(dict(d["channelThumbnailSupportedRenderers"], "channelThumbnailWithLinkRenderer", "thumbnail"))

        return YTVideo(id: id,
                       title: text(d["headline"]).isEmpty ? text(d["title"]) : text(d["headline"]),
                       channel: text(byline),
                       channelPath: channelPath,
                       avatarURL: avatar,
                       views: views,
                       published: text(d["publishedTimeText"]),
                       duration: isLive ? "" : duration,
                       isLive: isLive,
                       isShort: false,
                       thumbnail: bestImage(d["thumbnail"]))
    }

    private static func shortVideo(_ d: [String: Any]?) -> YTVideo? {
        guard let d else { return nil }
        var id = value(d, ["onTap", "innertubeCommand", "reelWatchEndpoint", "videoId"]) as? String
        if id == nil, let entity = d["entityId"] as? String, let last = entity.split(separator: "-").last {
            id = String(entity.hasPrefix("shorts-shelf-item-") ? entity.dropFirst("shorts-shelf-item-".count) : last)
        }
        guard let id else { return nil }
        let image = bestImage(dict(d["thumbnailViewModel"], "thumbnailViewModel", "image"))
            ?? bestImage(dict(d["thumbnail"], "sources"))
        return YTVideo(id: id,
                       title: text(dict(d["overlayMetadata"], "primaryText")),
                       channel: "",
                       channelPath: nil,
                       avatarURL: nil,
                       views: text(dict(d["overlayMetadata"], "secondaryText")),
                       published: "",
                       duration: "",
                       isLive: false,
                       isShort: true,
                       thumbnail: image)
    }

    private static func reelVideo(_ d: [String: Any]?) -> YTVideo? {
        guard let d, let id = d["videoId"] as? String else { return nil }
        return YTVideo(id: id, title: text(d["headline"]), channel: "", channelPath: nil, avatarURL: nil,
                       views: text(d["viewCountText"]), published: "", duration: "", isLive: false, isShort: true,
                       thumbnail: bestImage(d["thumbnail"]))
    }

    private static func lockupVideo(_ d: [String: Any]?) -> YTVideo? {
        guard let d, let id = d["contentId"] as? String,
              (d["contentType"] as? String ?? "LOCKUP_CONTENT_TYPE_VIDEO") == "LOCKUP_CONTENT_TYPE_VIDEO" else { return nil }
        let meta = dict(d["metadata"], "lockupMetadataViewModel")
        let rows = (value(meta, ["metadata", "contentMetadataViewModel", "metadataRows"]) as? [[String: Any]]) ?? []
        let parts = rows.map { row in
            ((row["metadataParts"] as? [[String: Any]]) ?? []).map { text($0["text"]) }.filter { !$0.isEmpty }
        }
        let channel = parts.first?.first ?? ""
        let details = parts.dropFirst().flatMap { $0 }
        var duration = ""
        if let overlays = value(d, ["contentImage", "thumbnailViewModel", "overlays"]) as? [[String: Any]] {
            for overlay in overlays {
                let badges = value(overlay, ["thumbnailOverlayBadgeViewModel", "thumbnailBadges"]) as? [[String: Any]] ?? []
                for badge in badges {
                    let t = text(dict(badge, "thumbnailBadgeViewModel")?["text"])
                    if !t.isEmpty { duration = t }
                }
            }
        }
        return YTVideo(id: id,
                       title: text(meta?["title"]),
                       channel: channel,
                       channelPath: nil,
                       avatarURL: nil,
                       views: details.first ?? "",
                       published: details.dropFirst().first ?? "",
                       duration: duration == "LIVE" ? "" : duration,
                       isLive: duration == "LIVE",
                       isShort: false,
                       thumbnail: bestImage(value(d, ["contentImage", "thumbnailViewModel", "image"])))
    }

    // MARK: Watch page

    static func watchInfo(playerResponse: Any?, initialData: Any?) -> YTWatchInfo? {
        guard let details = dict(playerResponse, "videoDetails"),
              let id = details["videoId"] as? String else { return nil }
        let micro = dict(playerResponse, "microformat", "playerMicroformatRenderer")

        var avatar: URL?
        var channelPath: String?
        func findOwner(_ any: Any?, depth: Int) {
            guard avatar == nil, depth < 80 else { return }
            if let d = any as? [String: Any] {
                for key in ["slimOwnerRenderer", "videoOwnerRenderer"] {
                    if let owner = d[key] as? [String: Any] {
                        avatar = bestImage(owner["thumbnail"]) ?? bestImage(owner["channelThumbnail"])
                        let endpoint = owner["navigationEndpoint"] ?? owner["channelUrl"]
                        channelPath = (value(endpoint, ["browseEndpoint", "canonicalBaseUrl"]) as? String)
                            ?? (value(endpoint, ["commandMetadata", "webCommandMetadata", "url"]) as? String)
                        return
                    }
                }
                for child in d.values { findOwner(child, depth: depth + 1) }
            } else if let a = any as? [Any] {
                for child in a { findOwner(child, depth: depth + 1) }
            }
        }
        findOwner(initialData, depth: 0)
        if channelPath == nil, let channelID = details["channelId"] as? String { channelPath = "/channel/\(channelID)" }

        let isLive = (details["isLiveContent"] as? Bool ?? false) && (details["isLive"] as? Bool ?? (micro?["liveBroadcastDetails"] != nil))
        let viewCount = Int(details["viewCount"] as? String ?? "") ?? 0
        let related = videos(in: initialData).filter { $0.id != id && !$0.isShort }

        return YTWatchInfo(videoID: id,
                           title: details["title"] as? String ?? "",
                           channel: details["author"] as? String ?? "",
                           channelPath: channelPath,
                           avatarURL: avatar,
                           views: viewCount > 0 ? compactCount(viewCount) + (isLive ? " watching" : " views") : "",
                           published: formatDate(micro?["publishDate"] as? String),
                           description: details["shortDescription"] as? String ?? "",
                           isLive: isLive,
                           related: related)
    }

    /// 1234 → "1.2K", 8_500_000 → "8.5M".
    static func compactCount(_ n: Int) -> String {
        func fmt(_ v: Double, _ suffix: String) -> String {
            let rounded = (v * 10).rounded() / 10
            return (rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)) + suffix
        }
        switch n {
        case 1_000_000_000...: return fmt(Double(n) / 1_000_000_000, "B")
        case 1_000_000...: return fmt(Double(n) / 1_000_000, "M")
        case 1_000...: return fmt(Double(n) / 1_000, "K")
        default: return String(n)
        }
    }

    /// "2024-05-01" or "2024-05-01T10:00:00-07:00" → "May 1, 2024".
    static func formatDate(_ raw: String?) -> String {
        guard let raw, raw.count >= 10 else { return "" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(raw.prefix(10))) else { return "" }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .none
        return out.string(from: date)
    }
}
