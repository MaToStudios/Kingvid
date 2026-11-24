import SwiftUI

struct TabSwitcherView: View {
    @EnvironmentObject var browser: BrowserStore
    @EnvironmentObject var app: AppModel

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(browser.tabs) { tab in
                        TabCard(tab: tab, isSelected: tab.id == browser.selectedID) {
                            browser.select(tab)
                            app.sheet = nil; app.section = .browser
                        } onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                browser.close(tab)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\(browser.tabs.count) \(browser.tabs.count == 1 ? "TAB" : "TABS")")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .tracking(2.4)
                        .foregroundStyle(Theme.goldGradientHorizontal)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close All", role: .destructive) {
                        browser.closeAll()
                        app.sheet = nil; app.section = .browser
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { app.sheet = nil; app.section = .browser }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.gold)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        browser.newTab(isPrivate: true)
                        app.sheet = nil; app.section = .browser
                    } label: {
                        Label("Private", systemImage: "eye.slash")
                    }
                    Spacer()
                    Button {
                        browser.newTab()
                        app.sheet = nil; app.section = .browser
                    } label: {
                        Label("New Tab", systemImage: "plus")
                    }
                    .buttonStyle(GoldButtonStyle(compact: true))
                }
            }
            .toolbarBackground(Theme.surface, for: .bottomBar)
            .toolbarColorScheme(.dark, for: .bottomBar)
        }
        .tint(Theme.gold)
    }
}

private struct TabCard: View {
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Button(action: onSelect) {
                    ZStack {
                        Theme.surface
                        if let snapshot = tab.snapshot, !tab.showsHome {
                            Image(uiImage: snapshot)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        } else {
                            CrownLogo().frame(width: 52, height: 52).opacity(0.85)
                        }
                    }
                    .frame(height: 170)
                    .clipped()
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.black.opacity(0.65)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
                }
                .buttonStyle(IconPressStyle())
                .padding(8)
            }

            HStack(spacing: 6) {
                if tab.isPrivate {
                    Image(systemName: "eye.slash.fill").font(.system(size: 11)).foregroundStyle(Theme.gold)
                }
                Text(label)
                    .font(Theme.ui(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Theme.surfaceElevated)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.hairline),
                              lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? Theme.gold.opacity(0.25) : .black.opacity(0.4), radius: 10, y: 4)
    }

    private var label: String {
        if tab.showsHome || tab.url == nil { return "Start Page" }
        return tab.title.isEmpty ? (tab.url?.host ?? "Loading…") : tab.title
    }
}
