import SwiftUI

/// The KingVid crown. A plain pre-rendered image (see tools/make_icons.py): no overlays, masks,
/// blend modes or shadows are layered on top, so it always renders as one clean, centred object.
struct CrownLogo: View {
    var body: some View {
        Image(Theme.accent.crownAsset)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .accessibilityLabel("KingVid crown")
    }
}

/// Crown with a soft radial glow *behind* it. The glow is a circle that fades to fully transparent at its
/// own edge and is never clipped, so it can't leave a hard horizontal edge (the "bar" artefact).
struct CrownHero: View {
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.gold.opacity(0.26), Theme.gold.opacity(0.0)],
                                     center: .center, startRadius: size * 0.2, endRadius: size * 1.1))
                .frame(width: size * 2.2, height: size * 2.2)
                .allowsHitTesting(false)
            CrownLogo()
                .frame(width: size, height: size)
        }
        .frame(width: size * 1.6, height: size * 1.25)
    }
}

/// Wordmark: serif, widely tracked, gold gradient.
struct KingVidWordmark: View {
    var size: CGFloat = 26
    var body: some View {
        Text("KINGVID")
            .font(Theme.display(size, weight: .bold))
            .tracking(size * 0.28)
            .foregroundStyle(Theme.goldGradientHorizontal)
    }
}
