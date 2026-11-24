import SwiftUI
import SwiftData

/// KingVid's home: crown, unified search, the YouTube entry card, recently played and quick access.
struct HomeScreen: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var youtube: YouTubeExperience
    @EnvironmentObject var library: LibraryStore

    @Query(sort: \FavoriteSite.sortIndex) private var favorites: [FavoriteSite]
    @Query(sort: \RecentMedia.lastPlayedAt, order: .reverse) private var recents: [RecentMedia]

    private enum Target: Hashable { case web, youtube }

    @State private var target: Target = .web
    @State private var text = ""
    @FocusState private var focused: Bool

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                header
                searchCard
                youtubeCard
                if !recents.isEmpty { continueSection }
                quickAccess
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            LinearGradient(colors: [Theme.surface, Theme.background], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            CrownHero(size: 104)
            KingVidWordmark(size: 30)
            Text("PREMIUM VIDEO BROWSER")
                .font(.system(size: 10, weight: .medium, design: .serif))
                .tracking(3.2)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: Search

    private var searchCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.goldGradientVertical)
                TextField(target == .web ? "Search the web or paste a link" : "Search YouTube", text: $text)
                    .font(Theme.ui(16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.gold)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(submit)
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(IconPressStyle())
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Capsule().fill(Theme.surface))
            .overlay(
                Capsule().strokeBorder(
                    focused ? AnyShapeStyle(Theme.goldGradient)
                            : AnyShapeStyle(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
                                                           startPoint: .top, endPoint: .bottom)),
                    lineWidth: focused ? 1.5 : 1)
            )

            GoldSegmented(selection: $target, items: [Target.web, Target.youtube],
                          title: { $0 == .web ? "Web" : "YouTube" })
                .frame(maxWidth: 240)
        }
    }

    private func submit() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        focused = false
        text = ""
        if target == .youtube {
            // A pasted YouTube link goes straight to the right place; anything else is a YouTube search.
            if let url = URLResolver.resolve(query), YouTubeURL.isYouTube(url), query.contains(".") {
                app.open(url)
            } else {
                app.section = .youtube
                youtube.search(query)
            }
        } else if let url = URLResolver.resolve(query) {
            app.open(url)
        }
    }

    // MARK: YouTube card

    private var youtubeCard: some View {
        Button { app.section = .youtube } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.goldGradient)
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.onGold)
                }
                .frame(width: 56, height: 56)
                .shadow(color: Theme.gold.opacity(0.3), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("YouTube")
                        .font(Theme.display(20))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Search, watch and keep listening with the screen off")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.goldGradientVertical)
            }
            .padding(16)
            .premiumCard(radius: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Theme.gold.opacity(0.6), Theme.gold.opacity(0.1)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
        }
        .buttonStyle(IconPressStyle())
    }

    // MARK: Continue

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Continue")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recents.prefix(8)) { item in
                        RecentCard(item: item) {
                            if let url = URL(string: item.pageURLString) { app.open(url) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Quick access

    private var quickAccess: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Quick access")
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(favorites) { fav in
                    Button {
                        if let url = URL(string: fav.urlString) { app.open(url) }
                    } label: {
                        ShortcutTile(title: fav.title, symbol: nil, monogram: fav.title)
                    }
                    .buttonStyle(IconPressStyle())
                    .contextMenu {
                        Button(role: .destructive) { library.delete(fav) } label: {
                            Label("Remove favorite", systemImage: "trash")
                        }
                    }
                }
                ForEach(FeaturedSite.all.filter { $0.name != "YouTube" }) { site in
                    Button {
                        if let url = URL(string: site.urlString) { app.open(url) }
                    } label: {
                        ShortcutTile(title: site.name, symbol: site.symbol, monogram: nil)
                    }
                    .buttonStyle(IconPressStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Text("Start a video, then lock your iPhone or switch apps.\nKingVid keeps the site's own player running.")
            .font(Theme.ui(12))
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
