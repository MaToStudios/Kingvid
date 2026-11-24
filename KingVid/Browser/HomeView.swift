import SwiftUI
import SwiftData

/// Start page: logo, continue listening, website shortcuts and favorites.
struct HomeView: View {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject var browser: BrowserStore
    @EnvironmentObject var library: LibraryStore

    @Query(sort: \FavoriteSite.sortIndex) private var favorites: [FavoriteSite]
    @Query(sort: \RecentMedia.lastPlayedAt, order: .reverse) private var recents: [RecentMedia]

    @State private var addingFavorite = false
    @State private var newTitle = ""
    @State private var newURL = ""

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                if !recents.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Continue")
                            .padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(recents.prefix(8)) { item in
                                    RecentCard(item: item) { open(item.pageURLString) }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !favorites.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Favorites")
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(favorites) { fav in
                                Button { open(fav.urlString) } label: {
                                    ShortcutTile(title: fav.title, symbol: nil, monogram: fav.title)
                                }
                                .buttonStyle(IconPressStyle())
                                .contextMenu {
                                    Button(role: .destructive) { library.delete(fav) } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLabel("Shortcuts")
                        Spacer()
                        Button {
                            newTitle = ""
                            newURL = ""
                            addingFavorite = true
                        } label: {
                            Label("Add favorite", systemImage: "plus")
                                .font(Theme.ui(13, weight: .semibold))
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(FeaturedSite.all) { site in
                            Button { open(site.urlString) } label: {
                                ShortcutTile(title: site.name, symbol: site.symbol, monogram: nil)
                            }
                            .buttonStyle(IconPressStyle())
                        }
                    }
                }
                .padding(.horizontal, 20)

                Text("Start a video, then lock your iPhone or switch apps.\nKingVid keeps the site's own player running.")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)
            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            LinearGradient(colors: [Theme.surface, Theme.background], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        .alert("Add Favorite", isPresented: $addingFavorite) {
            TextField("Name", text: $newTitle)
            TextField("Website address", text: $newURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add") {
                if let url = URLResolver.resolve(newURL), url.scheme?.hasPrefix("http") == true {
                    library.addFavorite(title: newTitle, urlString: url.absoluteString)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            CrownLogo(shimmer: true)
                .frame(width: 84, height: 84)
            KingVidWordmark(size: 26)
            Text("PREMIUM VIDEO BROWSER")
                .font(.system(size: 10, weight: .medium, design: .serif))
                .tracking(3)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 18)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        tab.load(url)
    }
}

private struct ShortcutTile: View {
    let title: String
    let symbol: String?
    let monogram: String?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.surfaceElevated, Theme.surface],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Theme.gold.opacity(0.7), Theme.gold.opacity(0.12)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.goldGradientVertical)
                } else {
                    Text(String((monogram ?? "?").prefix(1)).uppercased())
                        .font(Theme.display(26, weight: .bold))
                        .foregroundStyle(Theme.goldGradientVertical)
                }
            }
            .frame(width: 62, height: 62)

            Text(title)
                .font(Theme.ui(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RecentCard: View {
    let item: RecentMedia
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AsyncImage(url: item.artworkURLString.flatMap { URL(string: $0) }) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Theme.surfaceElevated
                            CrownLogo().padding(10)
                        }
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(Theme.ui(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(item.host)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: 130, alignment: .leading)
            }
            .padding(10)
            .premiumCard(radius: 16)
        }
        .buttonStyle(IconPressStyle())
    }
}
