import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var browser: BrowserStore
    @EnvironmentObject var media: MediaCenter
    @EnvironmentObject var youtube: YouTubeExperience

    // Observed only so the whole UI rebuilds when the appearance changes.
    @AppStorage(SettingsKey.appearanceAccent) private var accent = Theme.Accent.gold.rawValue
    @AppStorage(SettingsKey.appearanceBackground) private var backdrop = Theme.Backdrop.obsidian.rawValue

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            // Main layout: sections, then mini-player, then the tab bar. Safe areas are respected by the stack;
            // only the backgrounds extend under the status bar / home indicator.
            VStack(spacing: 0) {
                ZStack {
                    pane(.home) { HomeScreen() }
                    if app.visited.contains(.youtube) {
                        pane(.youtube) { YouTubeScreen() }
                    }
                    pane(.browser) {
                        if let tab = browser.selected {
                            BrowserScreen(tab: tab, ownership: media.ownership)
                        }
                    }
                    pane(.library) { LibraryView() }
                    pane(.settings) { SettingsView() }
                }
                if !app.isImmersive {
                    MiniPlayerView()
                    AppTabBar()
                }
            }

            // Full-screen YouTube watch screen. Mounted at the root (constant size) so its web view never resizes.
            YouTubeWatchView()
        }
        .id(accent + backdrop)
        .tint(Theme.gold)
        .sheet(item: $app.sheet) { sheet in
            Group {
                switch sheet {
                case .tabs: TabSwitcherView()
                case .player: PlayerSheet()
                }
            }
            .id(accent + backdrop)
            .tint(Theme.gold)
            .presentationBackground(Theme.background)
            .presentationDragIndicator(sheet == .player ? .hidden : .visible)
            .presentationCornerRadius(28)
        }
    }

    /// Every section stays alive once opened (so web views keep playing); only the selected one is visible.
    private func pane<Content: View>(_ section: AppSection, @ViewBuilder content: () -> Content) -> some View {
        let selected = app.section == section
        return content()
            .opacity(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
            .zIndex(selected ? 1 : 0)
    }
}
