import SwiftUI

/// Playback diagnostics: what the page players reported, the audio session, and a built-in test page with
/// MP4 / HLS / MP3 players so you can tell "this site is the problem" from "the app is the problem".
struct DiagnosticsView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var browser: BrowserStore
    @EnvironmentObject var media: MediaCenter
    @ObservedObject private var log = DiagnosticsLog.shared

    @State private var copied = false

    var body: some View {
        List {
            Section {
                row("Audio session", DiagnosticsLog.audioSessionSummary())
                row("User agent", WebViewFactory.userAgentSuffix)
                row("PiP supported", media.pipSupported ? "yes" : "no")
                if let s = media.session {
                    row("Session", "\(s.isPlaying ? "playing" : "paused") · \(s.isVideo ? "video" : "audio") · \(s.host)")
                    row("Position", "\(formatTime(s.position)) / \(s.isLive ? "live" : formatTime(s.duration))")
                } else {
                    row("Session", "none")
                }
                if let error = media.lastError { row("Last error", error) }
            } header: {
                SectionLabel("Status")
            }
            .listRowBackground(Theme.surface)

            Section {
                Button {
                    let tab = browser.newTab()
                    tab.loadHTML(PlaybackTestPage.html, title: "KingVid playback test")
                    app.section = .browser
                } label: {
                    Label("Open playback test page", systemImage: "play.rectangle.on.rectangle")
                }
                Button {
                    UIPasteboard.general.string = log.report(session: media.session, tabs: browser.tabs.count)
                    copied = true
                } label: {
                    Label(copied ? "Copied to clipboard" : "Copy diagnostic report", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) { log.clear() } label: {
                    Label("Clear log", systemImage: "trash")
                }
            } header: {
                SectionLabel("Tools")
            } footer: {
                Text("The test page plays a sample MP4, an HLS stream and an MP3 and shows each player's real state. If those work but a website doesn't, the problem is that website.")
            }
            .listRowBackground(Theme.surface)

            Section {
                if log.entries.isEmpty {
                    Text("No events yet. Play something, then come back.")
                        .font(Theme.ui(13)).foregroundStyle(Theme.textSecondary)
                }
                ForEach(log.entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.date.formatted(date: .omitted, time: .standard)) · \(entry.category)")
                            .font(Theme.ui(10, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                        Text(entry.message)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                SectionLabel("Event log")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Playback diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.ui(12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 2)
    }
}

/// Self-contained page with three real players; each shows its own readyState / error so failures are visible.
enum PlaybackTestPage {
    static let html = #"""
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>KingVid playback test</title>
    <style>
      body{margin:0;padding:16px;background:#060607;color:#f5f0e4;font-family:-apple-system,Helvetica,sans-serif}
      h1{font-family:ui-serif,Georgia,serif;font-size:22px;margin:4px 0 4px;
         background:linear-gradient(135deg,#fbefb0,#d9b13f,#8f6a14);-webkit-background-clip:text;color:transparent}
      p.sub{color:#a29c8e;font-size:13px;margin:0 0 18px}
      section{background:#121214;border:1px solid #2a2a2e;border-radius:16px;padding:12px;margin-bottom:16px}
      h2{font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:#d9b13f;margin:0 0 8px}
      video,audio{width:100%;border-radius:10px;background:#000}
      pre{font-size:11px;color:#a29c8e;white-space:pre-wrap;margin:8px 0 0}
      .ok{color:#d9b13f}.bad{color:#ff8a65}
    </style></head><body>
    <h1>Playback test</h1>
    <p class="sub">Start each player. Then lock the phone / switch apps to test background audio.</p>

    <section><h2>MP4 (H.264)</h2>
      <video id="a" controls playsinline preload="metadata"
        src="https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4"></video><pre id="sa"></pre></section>

    <section><h2>HLS stream</h2>
      <video id="b" controls playsinline preload="metadata"
        src="https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"></video><pre id="sb"></pre></section>

    <section><h2>MP3 audio</h2>
      <audio id="c" controls preload="metadata"
        src="https://interactive-examples.mdn.mozilla.net/media/cc0-audio/t-rex-roar.mp3"></audio><pre id="sc"></pre></section>

    <script>
      var names = {1:'aborted',2:'network error',3:'decode error',4:'format not supported'};
      ['a','b','c'].forEach(function(id){
        var el = document.getElementById(id), out = document.getElementById('s'+id);
        function show(){
          var e = el.error;
          out.innerHTML = 'readyState=' + el.readyState + ' networkState=' + el.networkState +
            ' paused=' + el.paused + ' t=' + el.currentTime.toFixed(1) + '/' + (isFinite(el.duration)?el.duration.toFixed(1):'?') +
            (e ? '<br><span class="bad">error ' + e.code + ' (' + (names[e.code]||'?') + ') ' + (e.message||'') + '</span>' : '<br><span class="ok">no error</span>');
        }
        ['loadedmetadata','canplay','playing','pause','timeupdate','error','stalled','waiting','ended'].forEach(function(ev){ el.addEventListener(ev, show); });
        show();
      });
      var probe = document.createElement('video');
      document.body.insertAdjacentHTML('beforeend', '<pre>MediaSource: ' + (typeof window.MediaSource) +
        ' · ManagedMediaSource: ' + (typeof window.ManagedMediaSource) +
        ' · HLS: ' + (probe.canPlayType('application/vnd.apple.mpegurl')||'no') + '</pre>');
    </script></body></html>
    """#
}
