# KingVid

Premium iOS video browser (SwiftUI, WKWebView, AVFoundation, AVKit, MediaPlayer, SwiftData, iOS 17+).
Black / graphite UI with metallic gold accents and a crown logo.

## Install on iPhone (no Mac, free Apple ID, Sideloadly)

1. Download the latest IPA: <https://github.com/MaToStudios/Kingvid/releases/latest> (`KingVid.ipa`).
   Direct link for build 5: <https://github.com/MaToStudios/Kingvid/releases/download/build-5/KingVid.ipa>
   (Release `build-2` is a broken build with no executable; ignore it.)
2. Install [Sideloadly](https://sideloadly.io) on your Windows PC (also install iTunes and iCloud from
   apple.com, *not* the Microsoft Store versions, if Sideloadly asks for them).
3. Connect the iPhone by USB, unlock it and tap **Trust**.
4. Open Sideloadly, drag `KingVid.ipa` into it, enter your Apple ID, and press **Start**.
   (If Sideloadly offers a bundle identifier field, leave it or pick any unique one.)
5. On the iPhone: **Settings → General → VPN & Device Management → your Apple ID → Trust**.
   iOS 16+: also enable **Settings → Privacy & Security → Developer Mode** and restart.
6. Open KingVid.

Free Apple IDs expire apps after **7 days** and allow 3 sideloaded apps at once; re-run Sideloadly to refresh.

## What's in the app

Home (search, YouTube card, recents, quick access) · YouTube · Browser (tabs, history, bookmarks) · Library · Settings.
Settings > Troubleshooting > Playback diagnostics has a test page (MP4, HLS, MP3) and a copyable report.

### YouTube

- **Feed (native):** categories and search results built from YouTube's own page data (`YouTube/YouTubeData.swift`,
  `YouTubeService.swift`), thumbnail-first cards, Shorts shelf, continue watching. Account pages (subscriptions,
  library, playlists, channels, sign-in) open the real YouTube site.
- **Watch screen:** the original YouTube player runs in a dedicated web view that the player script reduces to
  *only the video* (`Media/YouTubeScripts.swift`); the video fills a full-width area sized to its real aspect
  ratio. KingVid draws one auto-hiding control overlay on top (no second control set). Details, actions and
  Up next are native below. Fullscreen rotates to landscape with the same controls.

## Tests

- `tools/js-tests/run.sh` – injected page scripts (background playback bridge, YouTube interception,
  video-only layout, ad/mute handling) in headless Chromium.
- `tools/youtube-parser-test/run.sh` – parser against a freshly downloaded YouTube results page.

## How the build works

`project.yml` (XcodeGen) → `.github/workflows/build-ipa.yml` builds an **unsigned** Release IPA on a macOS
runner and publishes it as a GitHub Release (`build-N`). The job fails (and publishes nothing) if the compile fails or the
IPA has no executable. Sideloadly signs it with your Apple ID.

## Background playback design

The site's own player keeps running; nothing is extracted or replaced. `KingVid/Media/MediaScripts.swift` injects
a script into every frame that (1) spoofs the Page Visibility API so sites don't pause when hidden, (2) resumes
media that WebKit/the page pauses while the app is backgrounded, (3) reports playback state and metadata to
native code, and (4) exposes a command API. `MediaCenter` drives the audio session, Now Playing / Lock Screen
commands, interruptions and Picture in Picture. Behaviour varies per website; see Settings → Background Playback.

Regenerate icons: `python3 tools/make_icons.py`.
