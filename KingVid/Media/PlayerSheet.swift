import SwiftUI

/// Expanded player: scrubber, transport, speed, Picture in Picture and AirPlay.
struct PlayerSheet: View {
    @EnvironmentObject var media: MediaCenter
    @EnvironmentObject var browser: BrowserStore
    @EnvironmentObject var app: AppModel

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let s = media.session {
                content(s)
            } else {
                VStack(spacing: 14) {
                    CrownLogo().frame(width: 90, height: 90)
                    Text("Nothing playing")
                        .font(Theme.display(20))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .onChange(of: media.session == nil) { _, isNil in
            if isNil { app.sheet = nil }
        }
    }

    private func content(_ s: MediaSession) -> some View {
        VStack(spacing: 22) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 38, height: 5).padding(.top, 8)

            HStack {
                Button { app.sheet = nil } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.goldGradientVertical)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(IconPressStyle())
                Spacer()
                Text("NOW PLAYING")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .tracking(2.4)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)

            ArtworkView(image: media.artwork, size: 280, corner: 26)
                .shadow(color: Theme.gold.opacity(0.25), radius: 30, y: 14)
                .scaleEffect(s.isPlaying ? 1 : 0.92)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: s.isPlaying)

            VStack(spacing: 6) {
                Text(s.title)
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(s.artist.isEmpty ? s.host : s.artist)
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 28)

            scrubber(s)
            transport(s)
            secondary(s)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
    }

    private func scrubber(_ s: MediaSession) -> some View {
        VStack(spacing: 4) {
            if s.isLive {
                HStack {
                    Circle().fill(Theme.gold).frame(width: 8, height: 8)
                    Text("LIVE").font(Theme.ui(12, weight: .bold)).tracking(1.5).foregroundStyle(Theme.gold)
                }
                .frame(height: 30)
            } else {
                Slider(
                    value: Binding(
                        get: { scrubbing ? scrubValue : s.position },
                        set: { scrubValue = $0 }
                    ),
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
                .font(Theme.ui(12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 28)
    }

    private func transport(_ s: MediaSession) -> some View {
        HStack(spacing: 22) {
            if s.hasPrevious {
                transportButton("backward.fill", size: 24) { media.previous() }
            }
            transportButton("gobackward.\(Int(Prefs.skipInterval))", size: 30, enabled: !s.isLive) {
                media.skip(-Prefs.skipInterval)
            }

            Button { media.toggle() } label: {
                Image(systemName: s.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.onGold)
                    .frame(width: 78, height: 78)
                    .background(Circle().fill(Theme.goldGradient))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: Theme.gold.opacity(0.45), radius: 16, y: 6)
            }
            .buttonStyle(IconPressStyle())

            transportButton("goforward.\(Int(Prefs.skipInterval))", size: 30, enabled: !s.isLive) {
                media.skip(Prefs.skipInterval)
            }
            if s.hasNext {
                transportButton("forward.fill", size: 24) { media.next() }
            }
        }
    }

    private func transportButton(_ name: String, size: CGFloat, enabled: Bool = true,
                                 action: @escaping () -> Void) -> some View {
        GoldIconButton(systemName: name, size: size, enabled: enabled, action: action)
    }

    private func secondary(_ s: MediaSession) -> some View {
        HStack(spacing: 10) {
            if s.isVideo && media.pipSupported {
                pill(s.pipActive ? "pip.exit" : "pip.enter", s.pipActive ? "Exit PiP" : "PiP") {
                    media.togglePiP()
                }
            }

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        media.setRate(rate)
                    } label: {
                        if abs(rate - s.rate) < 0.01 {
                            Label(rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(rateLabel(rate))
                        }
                    }
                }
            } label: {
                pillLabel("speedometer", rateLabel(s.rate))
            }

            Button {
                browser.showTab(withID: s.tabID)
                app.sheet = nil
            } label: {
                pillLabel("safari", "Page")
            }
            .buttonStyle(IconPressStyle())

            AirPlayPicker()
                .frame(width: 44, height: 44)
                .premiumCard(radius: 22)

            Button { media.closeSession() } label: {
                pillLabel("xmark", "Stop")
            }
            .buttonStyle(IconPressStyle())
        }
        .padding(.horizontal, 16)
    }

    private func pill(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { pillLabel(symbol, title) }
            .buttonStyle(IconPressStyle())
    }

    private func pillLabel(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            Text(title).font(Theme.ui(13, weight: .semibold))
        }
        .foregroundStyle(Theme.goldGradientVertical)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .premiumCard(radius: 22)
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%g×", rate)
    }
}
