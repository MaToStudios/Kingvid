import SwiftUI

/// Watch screen.
///
/// Layout (portrait): a full-width video area sized to the video's real aspect ratio, then native details
/// (title, channel, actions, description, up next). Landscape: the video fills the screen.
///
/// There is exactly ONE playback interface: the web view shows only the original YouTube video (YouTube's
/// own control layer is hidden by the player script), and KingVid draws a single overlay on top of it that
/// auto-hides while playing. The screen stays mounted while minimised so playback never restarts.
struct YouTubeWatchView: View {
    @EnvironmentObject var youtube: YouTubeExperience

    var body: some View {
        if let player = youtube.player {
            WatchScreen(player: player)
        }
    }
}

private struct WatchScreen: View {
    @ObservedObject var player: BrowserTab
    @EnvironmentObject var youtube: YouTubeExperience
    @EnvironmentObject var media: MediaCenter
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var landscape: Bool { verticalSizeClass == .compact }

    private var owned: MediaSession? {
        guard let s = media.session, s.tabID == player.id else { return nil }
        return s
    }

    var body: some View {
        GeometryReader { geo in
            if landscape {
                PlayerSurface(player: player, session: owned, landscape: true)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 0) {
                    PlayerSurface(player: player, session: owned, landscape: false)
                        .frame(width: geo.size.width, height: videoHeight(width: geo.size.width, available: geo.size.height))
                    WatchDetails(player: player, session: owned)
                }
            }
        }
        // Black behind the status bar and video, graphite behind the details.
        .background(
            VStack(spacing: 0) {
                Color.black.frame(height: landscape ? nil : 320)
                if !landscape { Theme.background }
            }
            .ignoresSafeArea()
        )
        .statusBarHidden(landscape && youtube.isWatching)
        // Always mounted so the web view never reloads; hidden by opacity when minimised.
        .opacity(youtube.isWatching ? 1 : 0)
        .offset(y: youtube.isWatching ? 0 : 60)
        .allowsHitTesting(youtube.isWatching)
        .accessibilityHidden(!youtube.isWatching)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: youtube.isWatching)
    }

    /// Full width; height follows the real video aspect (16:9 until known), capped so details stay visible.
    private func videoHeight(width: CGFloat, available: CGFloat) -> CGFloat {
        let aspect = (owned?.aspectRatio ?? 0) > 0.3 ? owned!.aspectRatio : 16.0 / 9.0
        return min(width / aspect, available * 0.62)
    }
}

// MARK: - Player surface (video + the single control overlay)

private struct PlayerSurface: View {
    @ObservedObject var player: BrowserTab
    let session: MediaSession?
    let landscape: Bool

    @EnvironmentObject var youtube: YouTubeExperience
    @EnvironmentObject var media: MediaCenter

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var seekFlash: Bool?   // true = forward, false = back
    @State private var flashToken = 0

    /// Until the page reports a playing/paused video, touches go to the page itself (consent or
    /// age-confirmation screens must stay usable). After that, the overlay owns the surface.
    private var pageInteractive: Bool { session == nil }

    var body: some View {
        ZStack {
            Color.black
            WebViewRepresentable(tab: player)
                .allowsHitTesting(pageInteractive)

            if !pageInteractive {
                gestureLayer
            }

            if let s = session {
                if controlsVisible || !s.isPlaying {
                    controls(s)
                        .transition(.opacity)
                } else if !s.isLive, s.duration > 0 {
                    thinProgress(s)
                }
                statusPills(s)
            } else {
                loadingLayer
            }

            if let forward = seekFlash {
                seekFlashView(forward: forward)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .onChange(of: session?.isPlaying) { _, _ in scheduleHide() }
        .onAppear { scheduleHide() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if !landscape, value.translation.height > 80, abs(value.translation.width) < 60 { youtube.minimize() }
            }
        )
    }

    // MARK: Gestures

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            tapZone(forward: false)
            tapZone(forward: true)
        }
    }

    private func tapZone(forward: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard let s = session, !s.isLive, !s.isAd else { return }
                media.skip(forward ? 10 : -10)
                flash(forward: forward)
            }
            .onTapGesture {
                controlsVisible.toggle()
                scheduleHide()
            }
    }

    private func flash(forward: Bool) {
        flashToken += 1
        let token = flashToken
        withAnimation(.easeOut(duration: 0.15)) { seekFlash = forward }
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            if token == flashToken { withAnimation(.easeIn(duration: 0.2)) { seekFlash = nil } }
        }
    }

    /// Keeps controls up briefly after any interaction; hides them while playing.
    private func scheduleHide() {
        hideTask?.cancel()
        guard controlsVisible, session?.isPlaying == true, !scrubbing else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
    }

    private func poke() {
        controlsVisible = true
        scheduleHide()
    }

    // MARK: Controls

    private func controls(_ s: MediaSession) -> some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.12), Color.black.opacity(0.12), Color.black.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topRow(s)
                Spacer(minLength: 0)
                centerRow(s)
                Spacer(minLength: 0)
                bottomArea(s)
            }
            .padding(.horizontal, landscape ? 44 : 4)
            .padding(.top, landscape ? 10 : 0)
            .padding(.bottom, landscape ? 14 : 0)
        }
    }

    private func topRow(_ s: MediaSession) -> some View {
        HStack(spacing: 2) {
            overlayButton("chevron.down", size: 19) {
                if landscape { OrientationController.set(landscape: false) }
                youtube.minimize()
            }
            .accessibilityLabel("Minimise")
            if s.isAd {
                Text("Ad")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.onGold)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.goldGradient))
            }
            Spacer(minLength: 0)
            AirPlayPicker(tint: .white)
                .frame(width: 40, height: 40)
            if media.pipSupported, s.isVideo {
                overlayButton(s.pipActive ? "pip.exit" : "pip.enter", size: 18) {
                    media.togglePiP()
                    poke()
                }
                .accessibilityLabel("Picture in Picture")
            }
            moreMenu(s)
        }
    }

    private func centerRow(_ s: MediaSession) -> some View {
        HStack(spacing: landscape ? 64 : 44) {
            overlayButton("gobackward.10", size: 24, enabled: !s.isLive && !s.isAd) {
                media.skip(-10)
                poke()
            }
            Button {
                media.toggle()
                poke()
            } label: {
                Image(systemName: s.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.goldGradientVertical)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(Color.black.opacity(0.38)))
                    .overlay(Circle().strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel(s.isPlaying ? "Pause" : "Play")
            overlayButton("goforward.10", size: 24, enabled: !s.isLive && !s.isAd) {
                media.skip(10)
                poke()
            }
        }
    }

    private func bottomArea(_ s: MediaSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if s.isLive {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.gold).frame(width: 7, height: 7)
                        Text("LIVE").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    }
                } else {
                    Text("\(formatTime(scrubbing ? scrubValue : s.position)) / \(formatTime(s.duration))")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.95))
                }
                Spacer(minLength: 0)
                overlayButton(landscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", size: 17) {
                    OrientationController.set(landscape: !landscape)
                    poke()
                }
                .accessibilityLabel(landscape ? "Exit full screen" : "Full screen")
            }
            .padding(.leading, 10)
            if !s.isLive, s.duration > 0 {
                Scrubber(position: s.position, duration: s.duration, enabled: !s.isAd,
                         scrubbing: $scrubbing, value: $scrubValue) { time in
                    media.seek(to: time)
                    poke()
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private func moreMenu(_ s: MediaSession) -> some View {
        Menu {
            Picker("Playback speed", selection: Binding(get: { (s.rate * 100).rounded() / 100 },
                                                        set: { media.setRate($0) })) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Text(rate == 1 ? "Normal speed" : String(format: "%g×", rate)).tag(rate)
                }
            }
            if let url = player.url {
                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            Button { player.webView.reload() } label: { Label("Reload video", systemImage: "arrow.clockwise") }
            Button(role: .destructive) {
                if landscape { OrientationController.set(landscape: false) }
                youtube.closePlayer()
            } label: { Label("Stop & close", systemImage: "xmark.circle") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .shadow(color: .black.opacity(0.5), radius: 3)
        }
        .accessibilityLabel("More")
    }

    private func overlayButton(_ symbol: String, size: CGFloat, enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.95 : 0.35))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .shadow(color: .black.opacity(0.5), radius: 3)
        }
        .buttonStyle(IconPressStyle())
        .disabled(!enabled)
    }

    private func thinProgress(_ s: MediaSession) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.18))
                Rectangle().fill(Theme.goldGradientHorizontal)
                    .frame(width: geo.size.width * min(1, max(0, s.position / s.duration)))
            }
            .frame(height: 2)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }

    /// Unmute / skip-ad pills: shown whenever relevant, independent of the auto-hiding controls.
    @ViewBuilder private func statusPills(_ s: MediaSession) -> some View {
        VStack {
            if s.isMuted {
                Button { media.unmute() } label: {
                    Label("Tap to unmute", systemImage: "speaker.slash.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.onGold)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Capsule().fill(Theme.goldGradient))
                }
                .buttonStyle(IconPressStyle())
                .padding(.top, landscape ? 16 : 10)
            }
            Spacer(minLength: 0)
            if s.isAd, s.canSkipAd {
                HStack {
                    Spacer()
                    Button { media.skipAd() } label: {
                        HStack(spacing: 4) {
                            Text("Skip ad")
                            Image(systemName: "forward.end.fill")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(IconPressStyle())
                }
                .padding(.trailing, landscape ? 48 : 12)
                .padding(.bottom, landscape ? 64 : 48)
            }
        }
    }

    private var loadingLayer: some View {
        ZStack {
            VStack {
                HStack {
                    overlayButton("chevron.down", size: 19) {
                        if landscape { OrientationController.set(landscape: false) }
                        youtube.minimize()
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, landscape ? 44 : 4)
            if let error = media.lastError {
                VStack(spacing: 10) {
                    Text(error).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).multilineTextAlignment(.center)
                    Button("Retry") { player.webView.reload() }.buttonStyle(GoldButtonStyle(compact: true))
                }
                .padding(.horizontal, 24)
            } else if player.isLoading {
                ProgressView().tint(Theme.gold).scaleEffect(1.2).allowsHitTesting(false)
            }
        }
    }

    private func seekFlashView(forward: Bool) -> some View {
        HStack {
            if forward { Spacer() }
            Label("10 s", systemImage: forward ? "goforward" : "gobackward")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 36)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .padding(.horizontal, 36)
            if !forward { Spacer() }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

/// Thin gold seek bar that grows while dragging.
private struct Scrubber: View {
    let position: Double
    let duration: Double
    let enabled: Bool
    @Binding var scrubbing: Bool
    @Binding var value: Double
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let progress = duration > 0 ? min(1, max(0, (scrubbing ? value : position) / duration)) : 0
            let knob: CGFloat = scrubbing ? 16 : 11
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3))
                    .frame(height: scrubbing ? 5 : 3)
                Capsule().fill(Theme.goldGradientHorizontal)
                    .frame(width: width * progress, height: scrubbing ? 5 : 3)
                Circle().fill(Theme.goldLight)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: width * progress - knob / 2)
                    .opacity(enabled ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard enabled else { return }
                        scrubbing = true
                        value = min(1, max(0, g.location.x / width)) * duration
                    }
                    .onEnded { g in
                        guard enabled else { return }
                        let time = min(1, max(0, g.location.x / width)) * duration
                        value = time
                        onCommit(time)
                        scrubbing = false
                    }
            )
            .animation(.easeOut(duration: 0.15), value: scrubbing)
        }
        .frame(height: 26)
        .accessibilityElement()
        .accessibilityLabel("Seek")
        .accessibilityValue("\(formatTime(position)) of \(formatTime(duration))")
    }
}

// MARK: - Details below the video

private struct WatchDetails: View {
    @ObservedObject var player: BrowserTab
    let session: MediaSession?

    @EnvironmentObject var youtube: YouTubeExperience
    @EnvironmentObject var media: MediaCenter
    @EnvironmentObject var library: LibraryStore
    @State private var expanded = false

    private var info: YTWatchInfo? {
        guard let info = youtube.watchInfo, info.videoID == youtube.currentVideoID else { return nil }
        return info
    }

    private var title: String {
        if let info, !info.title.isEmpty { return info.title }
        if let session, !session.title.isEmpty { return session.title }
        let raw = player.title.replacingOccurrences(of: " - YouTube", with: "")
        return raw.isEmpty ? "Loading…" : raw
    }

    private var shareURL: URL? {
        guard let id = youtube.currentVideoID else { return player.url }
        return URL(string: "https://youtu.be/\(id)")
    }

    private var libraryURL: URL? {
        youtube.currentVideoID.flatMap { URL(string: "https://m.youtube.com/watch?v=\($0)") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                channelRow
                actionsRow
                if expanded, let description = info?.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 14)
                }
                upNext
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
    }

    private var titleBlock: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(expanded ? 5 : 2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    let meta = [info?.views ?? "", info?.published ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !meta.isEmpty {
                        Text(meta).foregroundStyle(Theme.textSecondary)
                    }
                    if !(info?.description ?? "").isEmpty {
                        Text(expanded ? "less" : "more").fontWeight(.semibold).foregroundStyle(Theme.textPrimary)
                    }
                }
                .font(.system(size: 12.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var channelRow: some View {
        HStack(spacing: 12) {
            YTAvatar(url: info?.avatarURL, name: info?.channel ?? session?.artist ?? "Y", size: 36)
            Text(info?.channel ?? session?.artist ?? " ")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let path = info?.channelPath {
                Button {
                    youtube.openChannel(path)
                } label: {
                    Text("View channel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.onGold)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(Capsule().fill(Theme.goldGradient))
                }
                .buttonStyle(IconPressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var actionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let url = shareURL {
                    ShareLink(item: url) { pillLabel("square.and.arrow.up", "Share") }
                }
                if let url = libraryURL {
                    let saved = library.isBookmarked(url)
                    Button { library.toggleBookmark(title: title, url: url) } label: {
                        pillLabel(saved ? "bookmark.fill" : "bookmark", saved ? "Saved" : "Save")
                    }
                    .buttonStyle(IconPressStyle())
                }
                if media.pipSupported, session?.isVideo == true {
                    Button { media.togglePiP() } label: {
                        pillLabel(session?.pipActive == true ? "pip.exit" : "pip.enter", "PiP")
                    }
                    .buttonStyle(IconPressStyle())
                }
                if let s = session {
                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Button(rate == 1 ? "Normal" : String(format: "%g×", rate)) { media.setRate(rate) }
                        }
                    } label: {
                        pillLabel("gauge.with.dots.needle.33percent", abs(s.rate - 1) < 0.01 ? "Speed" : String(format: "%g×", s.rate))
                    }
                }
                if let url = shareURL {
                    Button { UIPasteboard.general.string = url.absoluteString } label: {
                        pillLabel("link", "Copy link")
                    }
                    .buttonStyle(IconPressStyle())
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 16)
    }

    private func pillLabel(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(Theme.surfaceElevated))
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Up next")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            if let related = info?.related, !related.isEmpty {
                ForEach(related.prefix(30)) { video in
                    RelatedRow(video: video)
                }
            } else if info == nil {
                ForEach(0..<4, id: \.self) { _ in RelatedSkeleton() }
            } else {
                Text("No recommendations for this video.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14)
            }
        }
    }
}

private struct RelatedRow: View {
    let video: YTVideo
    @EnvironmentObject var youtube: YouTubeExperience

    var body: some View {
        Button { youtube.play(video.watchURL) } label: {
            HStack(alignment: .top, spacing: 12) {
                YTThumbnail(video: video, corner: 10)
                    .frame(width: 164, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !video.channel.isEmpty {
                        Text(video.channel)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    let meta = [video.views, video.published].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(IconPressStyle())
    }
}

private struct RelatedSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surfaceElevated).frame(width: 164, height: 92)
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceElevated).frame(height: 12)
                RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceElevated).frame(width: 110, height: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
