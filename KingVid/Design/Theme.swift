import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// KingVid design tokens. Black / graphite surfaces with metallic gold accents.
/// There is deliberately no blue or purple anywhere in the palette.
/// Appearance choices are read from UserDefaults; `RootView` rebuilds when they change.
enum Theme {
    enum Accent: String, CaseIterable, Identifiable {
        case gold, champagne, roseGold
        var id: String { rawValue }

        var title: String {
            switch self {
            case .gold: return "Royal Gold"
            case .champagne: return "Champagne"
            case .roseGold: return "Rose Gold"
            }
        }
        var light: Color {
            switch self {
            case .gold: return Color(hex: 0xFBEFB0)
            case .champagne: return Color(hex: 0xFFF6E3)
            case .roseGold: return Color(hex: 0xFBDDD0)
            }
        }
        var mid: Color {
            switch self {
            case .gold: return Color(hex: 0xD9B13F)
            case .champagne: return Color(hex: 0xE6CB93)
            case .roseGold: return Color(hex: 0xD9A48F)
            }
        }
        var deep: Color {
            switch self {
            case .gold: return Color(hex: 0x8F6A14)
            case .champagne: return Color(hex: 0x9E8350)
            case .roseGold: return Color(hex: 0x94614F)
            }
        }
    }

    enum Backdrop: String, CaseIterable, Identifiable {
        case obsidian, graphite
        var id: String { rawValue }

        var title: String { self == .obsidian ? "Obsidian Black" : "Graphite" }
        var base: Color { self == .obsidian ? Color(hex: 0x060607) : Color(hex: 0x131416) }
        var surface: Color { self == .obsidian ? Color(hex: 0x121214) : Color(hex: 0x1E1F22) }
        var elevated: Color { self == .obsidian ? Color(hex: 0x1D1E21) : Color(hex: 0x2A2B2F) }
    }

    static var accent: Accent {
        Accent(rawValue: UserDefaults.standard.string(forKey: SettingsKey.appearanceAccent) ?? "") ?? .gold
    }
    static var backdrop: Backdrop {
        Backdrop(rawValue: UserDefaults.standard.string(forKey: SettingsKey.appearanceBackground) ?? "") ?? .obsidian
    }

    // Gold
    static var goldLight: Color { accent.light }
    static var gold: Color { accent.mid }
    static var goldDeep: Color { accent.deep }

    static var goldGradient: LinearGradient {
        LinearGradient(colors: [accent.light, accent.mid, accent.deep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var goldGradientVertical: LinearGradient {
        LinearGradient(colors: [accent.light, accent.mid, accent.deep],
                       startPoint: .top, endPoint: .bottom)
    }
    static var goldGradientHorizontal: LinearGradient {
        LinearGradient(colors: [accent.deep, accent.mid, accent.light],
                       startPoint: .leading, endPoint: .trailing)
    }

    // Surfaces
    static var background: Color { backdrop.base }
    static var surface: Color { backdrop.surface }
    static var surfaceElevated: Color { backdrop.elevated }
    static var hairline: Color { Color.white.opacity(0.08) }

    // Text
    static var textPrimary: Color { Color(hex: 0xF5F0E4) }
    static var textSecondary: Color { Color(hex: 0xA29C8E) }
    static var textTertiary: Color { Color(hex: 0x6E695E) }
    static var onGold: Color { Color(hex: 0x1A1305) }

    // Typography: serif display for titles, SF for UI.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}
