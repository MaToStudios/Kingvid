import SwiftUI

/// Persistent bottom mini-player. Every control talks to the real page player via `MediaCenter`.
struct MiniPlayerView: View {
    @EnvironmentObject var media: MediaCenter
    @EnvironmentObject var app: AppModel

    var body: some View {
        Group {
            if let s = media.session {
                card(s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: media.session != nil)
    }

    private func card(_ s: MediaSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtworkView(image: media.artwork, size: 46, corner: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title)
                        .font(Theme.ui(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(s.artist.isEmpty ? s.host : s.artist)
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)

                Button { media.skip(-Prefs.skipInterval) } label: {
                    Image(systemName: "gobackward.\(Int(Prefs.skipInterval))")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.goldGradientVertical)
                        .frame(width: 34, height: 40)
                }
                .buttonStyle(IconPressStyle())
                .disabled(s.isLive)

                Button { media.toggle() } label: {
                    Image(systemName: s.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.onGold)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Theme.goldGradient))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
                        .shadow(color: Theme.gold.opacity(0.4), radius: 8, y: 3)
                }
                .buttonStyle(IconPressStyle())

                Button { media.skip(Prefs.skipInterval) } label: {
                    Image(systemName: "goforward.\(Int(Prefs.skipInterval))")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.goldGradientVertical)
                        .frame(width: 34, height: 40)
                }
                .buttonStyle(IconPressStyle())
                .disabled(s.isLive)

                Button { app.expandPlayer() } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 40)
                }
                .buttonStyle(IconPressStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if !s.isLive, s.duration > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.08))
                        Rectangle().fill(Theme.goldGradientHorizontal)
                            .frame(width: geo.size.width * min(1, max(0, s.position / s.duration)))
                    }
                }
                .frame(height: 2.5)
            }
        }
        .premiumCard(radius: 18)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onTapGesture { app.expandPlayer() }
    }
}
