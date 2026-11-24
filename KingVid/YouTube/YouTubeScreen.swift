import SwiftUI

/// The YouTube section: native top bar + route chips around the real YouTube mobile site.
struct YouTubeScreen: View {
    @EnvironmentObject var youtube: YouTubeExperience

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let browse = youtube.browse {
                BrowseContent(tab: browse)
            } else {
                ProgressView().tint(Theme.gold)
            }
            if youtube.showSearch {
                YouTubeSearchView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: youtube.showSearch)
    }
}

private struct BrowseContent: View {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject var youtube: YouTubeExperience
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            chips
            ZStack(alignment: .top) {
                WebViewRepresentable(tab: tab)
                if tab.isLoading {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.goldGradientHorizontal)
                            .frame(width: geo.size.width * max(0.06, tab.progress), height: 2.5)
                            .animation(.easeOut(duration: 0.25), value: tab.progress)
                    }
                    .frame(height: 2.5)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                if tab.canGoBack { tab.goBack() } else { youtube.open(route: .home) }
            } label: {
                Group {
                    if tab.canGoBack {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.goldGradientVertical)
                    } else {
                        CrownLogo().frame(width: 30, height: 30)
                    }
                }
                .frame(width: 38, height: 40)
            }
            .buttonStyle(IconPressStyle())

            Button { youtube.showSearch = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.goldGradientVertical)
                    Text("Search YouTube")
                        .font(Theme.ui(15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            accountMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.background)
    }

    private var accountMenu: some View {
        Menu {
            Button { youtube.signIn() } label: {
                Label("Sign in to YouTube", systemImage: "person.crop.circle.badge.checkmark")
            }
            Button { youtube.open(route: .library) } label: {
                Label("Your library", systemImage: "books.vertical")
            }
            Divider()
            Button { tab.reloadOrStop() } label: {
                Label(tab.isLoading ? "Stop loading" : "Reload page", systemImage: tab.isLoading ? "xmark" : "arrow.clockwise")
            }
            if let url = tab.url {
                ShareLink(item: url) { Label("Share page", systemImage: "square.and.arrow.up") }
                Button { app.showInBrowser(url) } label: {
                    Label("Open in Browser tab", systemImage: "safari")
                }
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.goldGradientVertical)
                .frame(width: 38, height: 40)
        }
    }

    // MARK: Route chips

    private var chips: some View {
        let active = YouTubeRoute.match(tab.url)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(YouTubeRoute.allCases) { route in
                    let selected = route == active
                    Button { youtube.open(route: route) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: route.symbol).font(.system(size: 12, weight: .semibold))
                            Text(route.title).font(Theme.ui(13, weight: .semibold))
                        }
                        .foregroundStyle(selected ? AnyShapeStyle(Theme.onGold) : AnyShapeStyle(Theme.textSecondary))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(
                            Capsule().fill(selected ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.surface))
                        )
                        .overlay(Capsule().strokeBorder(selected ? Color.white.opacity(0.3) : Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(IconPressStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Theme.background)
    }
}
