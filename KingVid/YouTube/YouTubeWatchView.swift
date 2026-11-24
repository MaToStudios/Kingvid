import SwiftUI

/// Full-screen watch screen. The page is the real YouTube watch page (original player, description,
/// comments, playlists, related videos); KingVid adds a native top bar and a native control dock that
/// mirror and drive the real video element. It stays mounted while minimised so playback never restarts.
struct YouTubeWatchView: View {
    @EnvironmentObject var youtube: YouTubeExperience

    var body: some View {
        if let player = youtube.player {
            WatchContent(player: player)
        }
    }
}

private struct WatchContent: View {
    @ObservedObject var player: BrowserTab
    @EnvironmentObject var youtube: YouTubeExperience
    @EnvironmentObject var media: MediaCenter
    @EnvironmentObject var app: AppModel

    private var owned: MediaSession? {
        guard let s = media.session, s.tabID == player.id else { return nil }
        return s
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .top) {
                WebViewRepresentable(tab: player)
                if player.isLoading {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.goldGradientHorizontal)
                            .frame(width: geo.size.width * max(0.06, player.progress), height: 2.5)
                            .animation(.easeOut(duration: 0.25), value: player.progress)
                    }
                    .frame(height: 2.5)
                    .allowsHitTesting(false)
                }
            }
            WatchControls(player: player, session: owned)
        }
        .background(Theme.background.ignoresSafeArea())
        // Always mounted at full size so the web view never resizes; hidden by opacity when minimised.
        .opacity(youtube.isWatching ? 1 : 0)
        .offset(y: youtube.isWatching ? 0 : 50)
        .allowsHitTesting(youtube.isWatching)
        .accessibilityHidden(!youtube.isWatching)
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: youtube.isWatching)
    }

    // MARK: Top bar

    private var title: String {
        if let owned { return owned.title }
        let raw = player.title.replacingOccurrences(of: " - YouTube", with: "")
        return raw.isEmpty ? "YouTube" : raw
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            Button { youtube.minimize() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.goldGradientVertical)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("Minimise player")

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.display(15))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("YouTube")
                    .font(Theme.ui(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)

            if media.pipSupported, owned?.isVideo == true {
                Button { media.togglePiP() } label: {
                    Image(systemName: owned?.pipActive == true ? "pip.exit" : "pip.enter")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.goldGradientVertical)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(IconPressStyle())
                .accessibilityLabel("Picture in Picture")
            }

            Menu {
                if let url = player.url {
                    ShareLink(item: url) { Label("Share video", systemImage: "square.and.arrow.up") }
                    Button { UIPasteboard.general.string = url.absoluteString } label: {
                        Label("Copy link", systemImage: "link")
                    }
                    Button {
                        youtube.minimize()
                        app.showInBrowser(url)
                    } label: {
                        Label("Open in Browser tab", systemImage: "safari")
                    }
                }
                Button { player.webView.reload() } label: {
                    Label("Reload video page", systemImage: "arrow.clockwise")
                }
                Divider()
                Button(role: .destructive) { youtube.closePlayer() } label: {
                    Label("Stop & close", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 21))
                    .foregroundStyle(Theme.goldGradientVertical)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 6)
        .background(Theme.background)
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                if value.translation.height > 60 { youtube.minimize() }
            }
        )
    }
}

/// Native control dock. Every control sends a real command to the page's video element; the displayed
/// state (position, duration, playing, speed, PiP) comes back from the page, never from guesses.
private struct WatchControls: View {
    @ObservedObject var player: BrowserTab
    let session: MediaSession?
    @EnvironmentObject var media: MediaCenter

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            if let s = session {
                scrubber(s)
                transport(s)
            } else {
                preparing
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            Theme.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(LinearGradient(colors: [Theme.gold.opacity(0), Theme.gold.opacity(0.45), Theme.gold.opacity(0)],
                                                    startPoint: .leading, endPoint: .trailing))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var preparing: some View {
        HStack(spacing: 12) {
            if let error = media.lastError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.gold)
                Text(error)
                    .font(Theme.ui(13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Spacer()
                Button("Retry") { player.webView.reload() }
                    .buttonStyle(GoldButtonStyle(compact: true))
            } else {
                ProgressView().tint(Theme.gold)
                Text("Waiting for the video to start…")
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
        }
        .frame(height: 62)
    }

    private func scrubber(_ s: MediaSession) -> some View {
        VStack(spacing: 2) {
            if s.isLive {
                HStack(spacing: 6) {
                    Circle().fill(Theme.gold).frame(width: 8, height: 8)
                    Text("LIVE").font(Theme.ui(12, weight: .bold)).tracking(1.5).foregroundStyle(Theme.gold)
                    Spacer()
                }
                .frame(height: 30)
            } else {
                Slider(
                    value: Binding(get: { scrubbing ? scrubValue : s.position }, set: { scrubValue = $0 }),
                    in: 0...max(1, s.duration),
                    onEditingChanged: { editing in
                        if editing {
                            scrubValue = s.position
                            scrubbing = true
                        } else {
                            media.seek(to: scrubValue)
                            scrubbing = false
                        }
                    }
                )
                .tint(Theme.gold)
                HStack {
                    Text(formatTime(scrubbing ? scrubValue : s.position))
                    Spacer()
                    Text("-" + formatTime(max(0, s.duration - (scrubbing ? scrubValue : s.position))))
                }
                .font(Theme.ui(11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func transport(_ s: MediaSession) -> some View {
        HStack(spacing: 0) {
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button { media.setRate(rate) } label: {
                        if abs(rate - s.rate) < 0.01 {
                            Label(rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(rateLabel(rate))
                        }
                    }
                }
            } label: {
                Text(rateLabel(s.rate))
                    .font(Theme.ui(14, weight: .bold))
                    .foregroundStyle(Theme.goldGradientVertical)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }

            if s.hasPrevious {
                dockButton("backward.fill") { media.previous() }
            }
            dockButton("gobackward.\(Int(Prefs.skipInterval))", enabled: !s.isLive) { media.skip(-Prefs.skipInterval) }

            Button { media.toggle() } label: {
                Image(systemName: s.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.onGold)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Theme.goldGradient))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: Theme.gold.opacity(0.4), radius: 10, y: 4)
            }
            .buttonStyle(IconPressStyle())
            .frame(maxWidth: .infinity)

            dockButton("goforward.\(Int(Prefs.skipInterval))", enabled: !s.isLive) { media.skip(Prefs.skipInterval) }
            if s.hasNext {
                dockButton("forward.fill") { media.next() }
            }

            AirPlayPicker()
                .frame(maxWidth: .infinity, minHeight: 48)
        }
    }

    private func dockButton(_ symbol: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(enabled ? AnyShapeStyle(Theme.goldGradientVertical) : AnyShapeStyle(Theme.textTertiary))
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconPressStyle())
        .disabled(!enabled)
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%g×", rate)
    }
}
