import SwiftUI
import SwiftData

struct LibraryView: View {
    enum Section: String, CaseIterable, Hashable {
        case favorites = "Favorites"
        case bookmarks = "Bookmarks"
        case history = "History"
        case recent = "Recent"
    }

    @EnvironmentObject var app: AppModel
    @State private var section: Section = .favorites

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GoldSegmented(selection: $section, items: Section.allCases, title: { $0.rawValue })
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Group {
                    switch section {
                    case .favorites: FavoritesList()
                    case .bookmarks: BookmarksList()
                    case .history: HistoryList()
                    case .recent: RecentList()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("LIBRARY")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .tracking(3)
                        .foregroundStyle(Theme.goldGradientHorizontal)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { app.sheet = nil }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.gold)
                }
            }
        }
        .tint(Theme.gold)
    }
}

// MARK: - Shared row

private struct LibraryRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    var trailing: String?
    var progress: Double?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.goldGradientVertical)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.surfaceElevated))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.ui(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if let progress, progress > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule().fill(Theme.goldGradientHorizontal)
                                .frame(width: geo.size.width * min(1, progress))
                        }
                    }
                    .frame(height: 3)
                }
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private func emptyState(_ symbol: String, _ title: String, _ message: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: symbol)
            .font(.system(size: 38, weight: .light))
            .foregroundStyle(Theme.goldGradientVertical)
        Text(title).font(Theme.display(19)).foregroundStyle(Theme.textPrimary)
        Text(message)
            .font(Theme.ui(14))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

private extension View {
    func libraryListStyle() -> some View {
        self.listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}

// MARK: - Favorites

private struct FavoritesList: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var library: LibraryStore
    @Query(sort: \FavoriteSite.sortIndex) private var favorites: [FavoriteSite]

    @State private var adding = false
    @State private var newTitle = ""
    @State private var newURL = ""

    var body: some View {
        Group {
            if favorites.isEmpty {
                VStack {
                    emptyState("star", "No favorites yet",
                               "Add favorite websites here, or from the ••• menu while browsing.")
                    Button("Add Favorite") { adding = true }
                        .buttonStyle(GoldButtonStyle())
                        .padding(.bottom, 40)
                }
            } else {
                List {
                    ForEach(favorites) { fav in
                        Button {
                            if let url = URL(string: fav.urlString) { app.open(url) }
                        } label: {
                            LibraryRow(symbol: "star.fill", title: fav.title, subtitle: fav.urlString)
                        }
                        .listRowBackground(Theme.background)
                        .listRowSeparatorTint(Theme.hairline)
                    }
                    .onDelete { offsets in
                        for index in offsets { library.delete(favorites[index]) }
                    }
                }
                .libraryListStyle()
                .safeAreaInset(edge: .bottom) {
                    Button { adding = true } label: {
                        Label("Add Favorite", systemImage: "plus")
                    }
                    .buttonStyle(GoldButtonStyle(compact: true))
                    .padding(.vertical, 10)
                }
            }
        }
        .alert("Add Favorite", isPresented: $adding) {
            TextField("Name", text: $newTitle)
            TextField("Website address", text: $newURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add") {
                if let url = URLResolver.resolve(newURL), url.scheme?.hasPrefix("http") == true {
                    library.addFavorite(title: newTitle, urlString: url.absoluteString)
                }
                newTitle = ""
                newURL = ""
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Bookmarks

private struct BookmarksList: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var library: LibraryStore
    @Query(sort: \Bookmark.createdAt, order: .reverse) private var bookmarks: [Bookmark]

    var body: some View {
        if bookmarks.isEmpty {
            emptyState("bookmark", "No bookmarks",
                       "Open the ••• menu on any page and choose Add Bookmark.")
        } else {
            List {
                ForEach(bookmarks) { bookmark in
                    Button {
                        if let url = URL(string: bookmark.urlString) { app.open(url) }
                    } label: {
                        LibraryRow(symbol: "bookmark.fill", title: bookmark.title, subtitle: bookmark.urlString)
                    }
                    .listRowBackground(Theme.background)
                    .listRowSeparatorTint(Theme.hairline)
                }
                .onDelete { offsets in
                    for index in offsets { library.delete(bookmarks[index]) }
                }
            }
            .libraryListStyle()
        }
    }
}

// MARK: - History

private struct HistoryList: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var library: LibraryStore
    @Query(HistoryList.descriptor) private var entries: [HistoryEntry]

    @State private var search = ""
    @State private var confirmClear = false

    static var descriptor: FetchDescriptor<HistoryEntry> {
        var d = FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.visitedAt, order: .reverse)])
        d.fetchLimit = 500
        return d
    }

    private var filtered: [HistoryEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.title.lowercased().contains(q) || $0.urlString.lowercased().contains(q) }
    }

    private var groups: [(day: Date, items: [HistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.visitedAt) }
        return grouped.keys.sorted(by: >).map { (day: $0, items: grouped[$0] ?? []) }
    }

    var body: some View {
        if entries.isEmpty {
            emptyState("clock", "No history", "Pages you visit will appear here.")
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search history", text: $search)
                        .foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button { confirmClear = true } label: {
                        Text("Clear").font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.gold)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Capsule().fill(Theme.surface))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                List {
                    ForEach(groups, id: \.day) { group in
                        Section {
                            ForEach(group.items) { entry in
                                Button {
                                    if let url = URL(string: entry.urlString) { app.open(url) }
                                } label: {
                                    LibraryRow(symbol: "clock", title: entry.title, subtitle: entry.urlString,
                                               trailing: entry.visitedAt.formatted(date: .omitted, time: .shortened))
                                }
                                .listRowBackground(Theme.background)
                                .listRowSeparatorTint(Theme.hairline)
                                .swipeActions {
                                    Button(role: .destructive) { library.delete(entry) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text(dayTitle(group.day))
                                .font(.system(size: 12, weight: .semibold, design: .serif))
                                .tracking(1.6)
                                .foregroundStyle(Theme.gold)
                        }
                    }
                }
                .libraryListStyle()
            }
            .confirmationDialog("Clear all browsing history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { library.clearHistory() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Recently played

private struct RecentList: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var library: LibraryStore
    @Query(sort: \RecentMedia.lastPlayedAt, order: .reverse) private var items: [RecentMedia]

    var body: some View {
        if items.isEmpty {
            emptyState("play.circle", "Nothing played yet",
                       "Videos and audio you play in KingVid show up here.")
        } else {
            List {
                ForEach(items) { item in
                    Button {
                        if let url = URL(string: item.pageURLString) { app.open(url) }
                    } label: {
                        LibraryRow(symbol: "play.fill", title: item.title,
                                   subtitle: item.artist.isEmpty ? item.host : "\(item.artist) · \(item.host)",
                                   trailing: item.duration > 0 ? formatTime(item.duration) : nil,
                                   progress: item.duration > 0 ? item.position / item.duration : nil)
                    }
                    .listRowBackground(Theme.background)
                    .listRowSeparatorTint(Theme.hairline)
                }
            }
            .libraryListStyle()
            .safeAreaInset(edge: .bottom) {
                Button("Clear Recent") { library.clearRecentMedia() }
                    .font(Theme.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                    .padding(.vertical, 12)
            }
        }
    }
}
