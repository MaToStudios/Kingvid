import SwiftUI

/// Search / URL bar with progress line, reload-stop, and the page actions menu.
struct AddressBar: View {
    @ObservedObject var tab: BrowserTab
    @Binding var isEditing: Bool
    @Binding var query: String

    @EnvironmentObject var browser: BrowserStore
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var app: AppModel

    @FocusState private var focused: Bool
    @State private var text = ""

    private var displayString: String {
        guard !tab.showsHome, let url = tab.url else { return "" }
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        HStack(spacing: 8) {
            if !focused {
                navButton("chevron.left", enabled: tab.canGoBackEffective) { tab.goBack() }
                if tab.canGoForward {
                    navButton("chevron.right", enabled: true) { tab.goForward() }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            field
            if focused {
                Button("Cancel") { focused = false }
                    .font(Theme.ui(15, weight: .medium))
                    .foregroundStyle(Theme.gold)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                tabsButton
                actionsMenu
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.background)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: focused)
        .onAppear { text = displayString }
        .onChange(of: tab.url) { _, _ in if !focused { text = displayString } }
        .onChange(of: tab.showsHome) { _, _ in if !focused { text = displayString } }
        .onChange(of: focused) { _, isFocused in
            isEditing = isFocused
            if isFocused {
                text = tab.showsHome ? "" : (tab.url?.absoluteString ?? "")
                query = text
            } else {
                text = displayString
            }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { focused = false }
        }
        .onChange(of: text) { _, newValue in
            if focused { query = newValue }
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            if let field = note.object as? UITextField {
                Task { @MainActor in field.selectAll(nil) }
            }
        }
    }

    // MARK: Navigation controls

    private func navButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(enabled ? AnyShapeStyle(Theme.goldGradientVertical) : AnyShapeStyle(Theme.textTertiary))
                .frame(width: 30, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconPressStyle())
        .disabled(!enabled)
    }

    private var tabsButton: some View {
        Button {
            tab.captureSnapshot()
            app.sheet = .tabs
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.goldGradient, lineWidth: 2)
                    .frame(width: 24, height: 24)
                Text("\(browser.tabs.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.goldGradient)
            }
            .frame(width: 32, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(IconPressStyle())
        .accessibilityLabel("Tabs")
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: leadingSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tab.isSecure && !tab.showsHome ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.textSecondary))
                .frame(width: 16)

            TextField("Search or enter website", text: $text)
                .font(Theme.ui(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.gold)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focused)
                .multilineTextAlignment(focused ? .leading : .center)
                .onSubmit {
                    browser.navigate(text, in: tab)
                    focused = false
                }

            if focused {
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(IconPressStyle())
                }
            } else {
                Button { tab.reloadOrStop() } label: {
                    Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.goldGradientVertical)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(IconPressStyle())
                .opacity(tab.showsHome ? 0.35 : 1)
                .disabled(tab.showsHome)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Capsule().fill(Theme.surface))
        .overlay(
            Capsule().strokeBorder(
                focused
                    ? AnyShapeStyle(Theme.goldGradient)
                    : AnyShapeStyle(LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                                                   startPoint: .top, endPoint: .bottom)),
                lineWidth: focused ? 1.5 : 1)
        )
        .overlay(alignment: .bottom) { progressLine }
        .clipShape(Capsule())
    }

    private var leadingSymbol: String {
        if focused || tab.showsHome { return "magnifyingglass" }
        if tab.isPrivate { return "eye.slash.fill" }
        return tab.isSecure ? "lock.fill" : "globe"
    }

    private var progressLine: some View {
        GeometryReader { geo in
            if tab.isLoading && !tab.showsHome {
                Rectangle()
                    .fill(Theme.goldGradientHorizontal)
                    .frame(width: geo.size.width * max(0.06, tab.progress), height: 2.5)
                    .animation(.easeOut(duration: 0.25), value: tab.progress)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Actions menu

    private var actionsMenu: some View {
        Menu {
            if let url = tab.url, !tab.showsHome {
                let bookmarked = library.isBookmarked(url)
                let favorite = library.isFavorite(url)
                Button {
                    library.toggleBookmark(title: tab.title, url: url)
                } label: {
                    Label(bookmarked ? "Remove Bookmark" : "Add Bookmark",
                          systemImage: bookmarked ? "bookmark.slash" : "bookmark")
                }
                Button {
                    library.toggleFavorite(title: tab.title, url: url)
                } label: {
                    Label(favorite ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: favorite ? "star.slash" : "star")
                }
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
                Divider()
            }
            Button {
                tab.toggleDesktopMode()
            } label: {
                Label(tab.desktopMode ? "Request Mobile Site" : "Request Desktop Site",
                      systemImage: tab.desktopMode ? "iphone" : "desktopcomputer")
            }
            Button {
                browser.newTab()
            } label: {
                Label("New Tab", systemImage: "plus.square")
            }
            Button {
                browser.newTab(isPrivate: true)
            } label: {
                Label("New Private Tab", systemImage: "eye.slash")
            }
            Button {
                tab.goHome()
            } label: {
                Label("Start Page", systemImage: "house")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.goldGradientVertical)
                .frame(width: 34, height: 42)
        }
    }
}
