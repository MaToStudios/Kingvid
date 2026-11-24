import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var browser: BrowserStore

    // Observed only so the whole UI rebuilds when the appearance changes.
    @AppStorage(SettingsKey.appearanceAccent) private var accent = Theme.Accent.gold.rawValue
    @AppStorage(SettingsKey.appearanceBackground) private var backdrop = Theme.Backdrop.obsidian.rawValue

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let tab = browser.selected {
                BrowserScreen(tab: tab)
            }
        }
        .id(accent + backdrop)
        .tint(Theme.gold)
        .sheet(item: $app.sheet) { sheet in
            Group {
                switch sheet {
                case .library: LibraryView()
                case .settings: SettingsView()
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
}
