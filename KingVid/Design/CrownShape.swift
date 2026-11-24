import SwiftUI

// Crown geometry. Coordinates mirror tools/make_icons.py so the in-app logo
// matches the app icon exactly.

private func crownPoint(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + x * rect.width,
            y: rect.minY + (0.10 + y * 0.80) * rect.height)
}

struct CrownBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let pts: [(CGFloat, CGFloat)] = [(0.12, 0.80), (0.07, 0.30), (0.29, 0.54), (0.50, 0.12),
                                         (0.71, 0.54), (0.93, 0.30), (0.88, 0.80)]
        p.move(to: crownPoint(pts[0].0, pts[0].1, in: rect))
        for pt in pts.dropFirst() {
            p.addLine(to: crownPoint(pt.0, pt.1, in: rect))
        }
        p.closeSubpath()
        return p
    }
}

struct CrownJewelsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let jewels: [(CGFloat, CGFloat, CGFloat)] = [(0.07, 0.25, 0.055), (0.50, 0.075, 0.060), (0.93, 0.25, 0.055)]
        for j in jewels {
            let c = crownPoint(j.0, j.1, in: rect)
            let r = j.2 * rect.width
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        return p
    }
}

struct CrownBandShape: Shape {
    func path(in rect: CGRect) -> Path {
        let a = crownPoint(0.14, 0.82, in: rect)
        let b = crownPoint(0.86, 0.97, in: rect)
        let r = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        return Path(roundedRect: r, cornerRadius: r.height / 2.2)
    }
}

struct CrownGemsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for gx in [CGFloat(0.29), 0.50, 0.71] {
            let c = crownPoint(gx, 0.895, in: rect)
            let r = 0.028 * rect.width
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        return p
    }
}

/// The KingVid crown: gold-gradient body, darker band, gems and a specular edge.
struct CrownLogo: View {
    var shimmer: Bool = false

    var body: some View {
        ZStack {
            CrownBodyShape().fill(Theme.goldGradientVertical)
            CrownJewelsShape().fill(Theme.goldGradientVertical)
            CrownBandShape().fill(
                LinearGradient(colors: [Theme.accent.mid, Theme.accent.deep],
                               startPoint: .top, endPoint: .bottom))
            CrownGemsShape().fill(Color(hex: 0x1E1404))
            CrownBodyShape().stroke(
                LinearGradient(colors: [Color.white.opacity(0.65), Color.white.opacity(0.05)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8)
        }
        .aspectRatio(1, contentMode: .fit)
        .modifier(OptionalShimmer(active: shimmer))
        .shadow(color: Theme.gold.opacity(0.28), radius: 14, y: 6)
    }
}

private struct OptionalShimmer: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.shimmer()
        } else {
            content
        }
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
