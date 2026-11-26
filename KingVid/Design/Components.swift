import SwiftUI
import AVKit

// MARK: - Button styles

struct GoldButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(compact ? 14 : 16, weight: .semibold))
            .foregroundStyle(Theme.onGold)
            .padding(.horizontal, compact ? 16 : 24)
            .padding(.vertical, compact ? 8 : 13)
            .background(Capsule().fill(Theme.goldGradient))
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .shadow(color: Theme.gold.opacity(0.35), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct IconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// Gold-gradient SF Symbol button used throughout the chrome.
struct GoldIconButton: View {
    let systemName: String
    var size: CGFloat = 20
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(enabled ? AnyShapeStyle(Theme.goldGradientVertical) : AnyShapeStyle(Theme.textTertiary))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconPressStyle())
        .disabled(!enabled)
    }
}

// MARK: - Surfaces

struct PremiumCard: ViewModifier {
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.surfaceElevated, Theme.surface],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
    }
}

extension View {
    func premiumCard(radius: CGFloat = 18) -> some View { modifier(PremiumCard(radius: radius)) }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold, design: .serif))
            .tracking(2.2)
            .foregroundStyle(Theme.goldGradientHorizontal)
    }
}

/// Segmented control in the gold style.
struct GoldSegmented<T: Hashable>: View {
    @Binding var selection: T
    let items: [T]
    let title: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = item }
                } label: {
                    Text(title(item))
                        .font(Theme.ui(13, weight: .semibold))
                        .foregroundStyle(selected ? Theme.onGold : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selected {
                                Capsule().fill(Theme.goldGradient)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    let image: UIImage?
    var size: CGFloat = 46
    var corner: CGFloat = 10

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Theme.surfaceElevated, Theme.background],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                CrownLogo().padding(size * 0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

struct AirPlayPicker: UIViewRepresentable {
    var tint: Color? = nil

    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(tint ?? Theme.gold)
        v.activeTintColor = UIColor(Theme.goldLight)
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Helpers

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
