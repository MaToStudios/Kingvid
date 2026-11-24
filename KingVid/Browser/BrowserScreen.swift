import SwiftUI

/// The main browsing screen: address bar, page area, mini-player and dock.
struct BrowserScreen: View {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject var browser: BrowserStore

    @State private var isEditing = false
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            AddressBar(tab: tab, isEditing: $isEditing, query: $query)

            ZStack {
                pages
                if isEditing {
                    SuggestionsList(query: query) { target in
                        browser.navigate(target, in: tab)
                        isEditing = false
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isEditing)

            MiniPlayerView()
            DockBar(tab: tab)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    /// The selected tab, plus the tab that owns active media (kept attached but invisible,
    /// so its player keeps running while you browse elsewhere).
    private var pages: some View {
        ZStack {
            ForEach(browser.tabs.filter { $0.id == tab.id || $0.id == browser.mediaTabID }) { t in
                TabPage(tab: t)
                    .opacity(t.id == tab.id ? 1 : 0)
                    .allowsHitTesting(t.id == tab.id)
                    .zIndex(t.id == tab.id ? 1 : 0)
            }
        }
    }
}

private struct TabPage: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        ZStack {
            WebViewRepresentable(tab: tab)
            if tab.showsHome {
                HomeView(tab: tab)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: tab.showsHome)
    }
}

private struct SuggestionsList: View {
    let query: String
    let onSelect: (String) -> Void

    @EnvironmentObject var library: LibraryStore

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let results = library.suggestions(for: trimmed)

        ScrollView {
            LazyVStack(spacing: 0) {
                if !trimmed.isEmpty {
                    row(symbol: "magnifyingglass", title: "Search “\(trimmed)”",
                        subtitle: SearchEngine.current.name, target: trimmed)
                }
                ForEach(results) { item in
                    row(symbol: symbol(for: item.kind), title: item.title,
                        subtitle: item.urlString, target: item.urlString)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
    }

    private func symbol(for kind: BrowserSuggestion.Kind) -> String {
        switch kind {
        case .favorite: return "star.fill"
        case .bookmark: return "bookmark.fill"
        case .history: return "clock"
        }
    }

    private func row(symbol: String, title: String, subtitle: String, target: String) -> some View {
        Button { onSelect(target) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.goldGradientVertical)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.ui(15, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(subtitle).font(Theme.ui(12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 60)
        }
    }
}
