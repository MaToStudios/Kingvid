import SwiftUI
import SwiftData

/// The YouTube section: compact native top bar + a native, thumbnail-first feed (home categories and search
/// results). Account pages (subscriptions, library, playlists, channels, sign-in) use the real YouTube site.
struct YouTubeScreen: View {
    @EnvironmentObject var youtube: YouTubeExperience

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                YTTopBar()
                if youtube.mode == .web, let browse = youtube.browse {
                    YTWebContent(tab: browse)
                } else {
                    YTFeedView()
                }
            }
            if youtube.showSearch {
                YouTubeSearchView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: youtube.showSearch)
    }
}

// MARK: - Top bar

private struct YTTopBar: View {
    @EnvironmentObject var youtube: YouTubeExperience
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 6) {
            leading
            Spacer(minLength: 8)
            Button { youtube.showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("Search YouTube")
            accountMenu
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(Theme.background)
    }

    @ViewBuilder private var leading: some View {
        switch youtube.mode {
        case .home:
            HStack(spacing: 8) {
                CrownLogo().frame(width: 24, height: 24)
                Text("YouTube")
                    .font(Theme.display(20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.leading, 4)
        case .results(let query):
            HStack(spacing: 2) {
                backButton { youtube.showHome() }
                Button { youtube.showSearch = true } label: {
                    Text(query)
                        .font(Theme.ui(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        case .web:
            if let browse = youtube.browse {
                YTWebHeader(tab: browse)
            }
        }
    }

    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.goldGradientVertical)
                .frame(width: 36, height: 40)
        }
        .buttonStyle(IconPressStyle())
        .accessibilityLabel("Back")
    }

    private var accountMenu: some View {
        Menu {
            Section {
                ForEach([YouTubeRoute.subscriptions, .library, .history, .watchLater, .liked]) { route in
                    Button { youtube.open(route: route) } label: {
                        Label(route.title, systemImage: route.symbol)
                    }
                }
            }
            Section {
                Button { youtube.signIn() } label: {
                    Label("Sign in to YouTube", systemImage: "person.crop.circle.badge.checkmark")
                }
                Button { youtube.browseTo(YouTubeRoute.home.url) } label: {
                    Label("YouTube website", systemImage: "globe")
                }
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.goldGradientVertical)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Your YouTube")
    }
}

/// Header while a real YouTube page is shown: back through the page's history, then back to the feed.
private struct YTWebHeader: View {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject var youtube: YouTubeExperience

    var body: some View {
        HStack(spacing: 2) {
            Button {
                if tab.canGoBack { tab.goBack() } else { youtube.showHome() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.goldGradientVertical)
                    .frame(width: 36, height: 40)
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("Back")
            Text(tab.title.replacingOccurrences(of: " - YouTube", with: "").isEmpty ? "YouTube" : tab.title.replacingOccurrences(of: " - YouTube", with: ""))
                .font(Theme.ui(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
    }
}

private struct YTWebContent: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        ZStack(alignment: .top) {
            WebViewRepresentable(tab: tab)
            if tab.isLoading {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.goldGradientHorizontal)
                        .frame(width: geo.size.width * max(0.06, tab.progress), height: 2)
                        .animation(.easeOut(duration: 0.25), value: tab.progress)
                }
                .frame(height: 2)
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Feed

private struct YTFeedView: View {
    @EnvironmentObject var youtube: YouTubeExperience
    @Query(sort: \RecentMedia.lastPlayedAt, order: .reverse) private var recents: [RecentMedia]

    private var isHome: Bool { youtube.mode == .home }

    private var continueItems: [RecentMedia] {
        Array(recents.filter { URL(string: $0.pageURLString).map(YouTubeURL.isWatch) ?? false }.prefix(10))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: isHome ? [.sectionHeaders] : []) {
                Section {
                    content
                } header: {
                    if isHome { YTCategoryBar() }
                }
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { youtube.loadFeed(force: true) }
        .background(Theme.background)
    }

    @ViewBuilder private var content: some View {
        switch youtube.feedState {
        case .idle, .loading:
            ForEach(0..<3, id: \.self) { _ in YTCardSkeleton() }
        case .failed(let message):
            YTFeedError(message: message)
        case .loaded:
            if isHome, youtube.category == .discover, !continueItems.isEmpty {
                YTContinueShelf(items: continueItems)
            }
            let regular = youtube.feed.filter { !$0.isShort }
            let shorts = youtube.feed.filter { $0.isShort }
            ForEach(Array(regular.enumerated()), id: \.element.id) { index, video in
                YTVideoCard(video: video)
                if index == 1, !shorts.isEmpty {
                    YTShortsShelf(shorts: shorts)
                }
            }
            if regular.isEmpty && shorts.isEmpty {
                YTFeedError(message: "No videos found.")
            }
        }
    }
}

private struct YTCategoryBar: View {
    @EnvironmentObject var youtube: YouTubeExperience

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(YTCategory.allCases) { category in
                    let selected = youtube.category == category
                    Button { youtube.select(category) } label: {
                        Text(category.title)
                            .font(Theme.ui(14, weight: .semibold))
                            .foregroundStyle(selected ? Theme.onGold : Theme.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(
                                Capsule().fill(selected ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.surfaceElevated))
                            )
                    }
                    .buttonStyle(IconPressStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Theme.background)
    }
}

/// Full-width video card: thumbnail first, then avatar + title + one metadata line.
struct YTVideoCard: View {
    let video: YTVideo
    @EnvironmentObject var youtube: YouTubeExperience

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { youtube.play(video.watchURL) } label: {
                YTThumbnail(video: video, corner: 14)
                    .aspectRatio(16 / 9, contentMode: .fit)
            }
            .buttonStyle(IconPressStyle())

            HStack(alignment: .top, spacing: 12) {
                Button {
                    if let path = video.channelPath { youtube.openChannel(path) }
                } label: {
                    YTAvatar(url: video.avatarURL, name: video.channel, size: 36)
                }
                .buttonStyle(.plain)
                .disabled(video.channelPath == nil)

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(video.metaLine)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { youtube.play(video.watchURL) }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 22)
    }
}

/// Thumbnail with duration / LIVE badge; falls back to YouTube's standard thumbnail if the large one fails.
struct YTThumbnail: View {
    let video: YTVideo
    var corner: CGFloat = 12
    var showsBadge = true
    @State private var useFallback = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle().fill(Theme.surfaceElevated)
                .overlay {
                    AsyncImage(url: useFallback ? video.fallbackThumbnail : video.largeThumbnail) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Color.clear.onAppear { if !useFallback { useFallback = true } }
                        default:
                            Color.clear
                        }
                    }
                }
                .clipped()
            if showsBadge {
                if video.isLive {
                    Text("LIVE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.onGold)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.goldGradient))
                        .padding(8)
                } else if !video.duration.isEmpty {
                    Text(video.duration)
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.78)))
                        .padding(8)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct YTAvatar: View {
    let url: URL?
    let name: String
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Theme.surfaceElevated)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Theme.gold)
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct YTShortsShelf: View {
    let shorts: [YTVideo]
    @EnvironmentObject var youtube: YouTubeExperience

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "play.square.stack.fill").foregroundStyle(Theme.goldGradientVertical)
                Text("Shorts").font(Theme.ui(17, weight: .bold)).foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shorts) { short in
                        Button { youtube.play(short.watchURL) } label: {
                            ZStack(alignment: .bottomLeading) {
                                YTThumbnail(video: short, corner: 12, showsBadge: false)
                                    .frame(width: 140, height: 248)
                                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(short.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if !short.views.isEmpty {
                                        Text(short.views).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                                .padding(8)
                            }
                            .frame(width: 140, height: 248)
                        }
                        .buttonStyle(IconPressStyle())
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 24)
    }
}

private struct YTContinueShelf: View {
    let items: [RecentMedia]
    @EnvironmentObject var youtube: YouTubeExperience

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continue watching")
                .font(Theme.ui(17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            if let url = URL(string: item.pageURLString) { youtube.play(url) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .bottom) {
                                    AsyncImage(url: item.artworkURLString.flatMap(URL.init(string:))) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Theme.surfaceElevated
                                    }
                                    .frame(width: 200, height: 112)
                                    .clipped()
                                    if item.duration > 0 {
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Rectangle().fill(Color.white.opacity(0.25))
                                                Rectangle().fill(Theme.gold)
                                                    .frame(width: geo.size.width * min(1, item.position / item.duration))
                                            }
                                        }
                                        .frame(height: 3)
                                    }
                                }
                                .frame(width: 200, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 200, alignment: .leading)
                            }
                        }
                        .buttonStyle(IconPressStyle())
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 24)
    }
}

private struct YTCardSkeleton: View {
    @State private var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surfaceElevated)
                .aspectRatio(16 / 9, contentMode: .fit)
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(Theme.surfaceElevated).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceElevated).frame(height: 13)
                    RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceElevated).frame(width: 180, height: 11)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 22)
        .opacity(dim ? 0.45 : 0.9)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

private struct YTFeedError: View {
    let message: String
    @EnvironmentObject var youtube: YouTubeExperience

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.goldGradientVertical)
            Text(message)
                .font(Theme.ui(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Try again") { youtube.loadFeed(force: true) }
                    .buttonStyle(GoldButtonStyle(compact: true))
                Button("YouTube website") { youtube.browseTo(YouTubeRoute.home.url) }
                    .font(Theme.ui(14, weight: .semibold))
                    .foregroundStyle(Theme.gold)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }
}
