// Parser test: compiles together with KingVid/YouTube/YouTubeData.swift on Linux or macOS.
// Usage: tools/youtube-parser-test/run.sh   (fetches a real m.youtube.com results page, then checks it)
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — " + detail)")
    if !ok { failures += 1 }
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "results.html"
guard let html = try? String(contentsOfFile: path, encoding: .utf8) else {
    print("cannot read \(path)"); exit(2)
}

let start = Date()
let json = YouTubeParser.initialJSON(named: "ytInitialData", in: html)
let parseTime = Date().timeIntervalSince(start)
check("ytInitialData located and decoded (JS string literal with \\x escapes)", json != nil, String(format: "%.2fs", parseTime))

let videos = YouTubeParser.videos(in: json)
let regular = videos.filter { !$0.isShort }
let shorts = videos.filter { $0.isShort }
check("found regular videos", regular.count >= 8, "\(regular.count) videos, \(shorts.count) shorts")
check("every video has id, title, thumbnail", videos.allSatisfy { $0.id.count == 11 && !$0.title.isEmpty && $0.fallbackThumbnail != nil })
check("regular videos have channel names", regular.filter { !$0.channel.isEmpty }.count >= regular.count - 1)
check("regular videos have channel paths", regular.filter { ($0.channelPath ?? "").hasPrefix("/") }.count >= regular.count - 1)
check("durations parsed for non-live videos", regular.filter { !$0.isLive && !$0.duration.isEmpty }.count >= 3)
check("live videos detected", regular.contains { $0.isLive })
check("avatars parsed", regular.filter { $0.avatarURL != nil }.count >= regular.count / 2)
check("no duplicate ids", Set(videos.map(\.id)).count == videos.count)
check("emoji survive decoding (surrogate pairs from \\u escapes)", videos.contains { $0.title.unicodeScalars.contains { $0.value > 0x1F000 } })
if !shorts.isEmpty {
    check("shorts have titles and 9:16 thumbnails", shorts.allSatisfy { !$0.title.isEmpty && $0.thumbnail != nil })
}
for v in regular.prefix(4) {
    print("   • [\(v.id)] \(v.title.prefix(48)) | \(v.metaLine) | \(v.isLive ? "LIVE" : v.duration)")
}

// Object-literal form (`var ytInitialPlayerResponse = {...};`) + watch info, built from the real items above.
if let first = regular.first {
    let player = """
    <script>var ytInitialPlayerResponse = {"videoDetails":{"videoId":"\(first.id)","title":"A \\"quoted\\" {title}","author":"\(first.channel)","channelId":"UCabc","viewCount":"8512345","shortDescription":"Line 1\\nLine 2","isLiveContent":false},"microformat":{"playerMicroformatRenderer":{"publishDate":"2024-05-01T10:00:00-07:00"}}};var other = 1;</script>
    """
    let pr = YouTubeParser.initialJSON(named: "ytInitialPlayerResponse", in: player)
    check("object-literal JSON with quotes/braces inside strings parsed", pr != nil)
    let info = YouTubeParser.watchInfo(playerResponse: pr, initialData: json)
    check("watch info: title/channel/views", info?.title == "A \"quoted\" {title}" && info?.channel == first.channel && info?.views == "8.5M views", "\(info?.views ?? "-")")
    check("watch info: description newlines kept", info?.description == "Line 1\nLine 2")
    check("watch info: date formatted", !(info?.published ?? "").isEmpty, info?.published ?? "")
    check("watch info: related excludes current video", (info?.related.count ?? 0) >= 5 && !(info?.related.contains { $0.id == first.id } ?? true), "\(info?.related.count ?? 0) related")
    check("watch info: channel path fallback", info?.channelPath == "/channel/UCabc" || (info?.channelPath ?? "").hasPrefix("/"))
}
check("compact counts", YouTubeParser.compactCount(999) == "999" && YouTubeParser.compactCount(1234) == "1.2K" && YouTubeParser.compactCount(8_500_000) == "8.5M" && YouTubeParser.compactCount(2_000_000) == "2M")

print(failures == 0 ? "\nALL PARSER TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
