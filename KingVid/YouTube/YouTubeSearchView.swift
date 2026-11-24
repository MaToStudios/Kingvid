import SwiftUI

/// Public YouTube search-suggestion endpoint (the same one browsers use for the omnibox).
enum YouTubeSuggestions {
    static func fetch(_ query: String) async -> [String] {
        var comps = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        comps?.queryItems = [URLQueryItem(name: "client", value: "firefox"),
                             URLQueryItem(name: "ds", value: "yt"),
                             URLQueryItem(name: "q", value: query)]
        guard let url = comps?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1, let list = json[1] as? [String] else { return [] }
        return Array(list.prefix(10))
    }
}

/// Native search screen: live suggestions, recent searches, then the results open in the YouTube view.
struct YouTubeSearchView: View {
    @EnvironmentObject var youtube: YouTubeExperience

    @State private var query = ""
    @State private var suggestions: [String] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.goldGradientVertical)
                    TextField("Search YouTube", text: $query)
                        .font(Theme.ui(16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.gold)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($focused)
                        .onSubmit { youtube.search(query) }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(IconPressStyle())
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(AnyShapeStyle(Theme.goldGradient), lineWidth: 1.5))

                Button("Cancel") { youtube.showSearch = false }
                    .font(Theme.ui(15, weight: .medium))
                    .foregroundStyle(Theme.gold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !youtube.recentSearches.isEmpty {
                        Section {
                            ForEach(youtube.recentSearches, id: \.self) { term in
                                row(symbol: "clock.arrow.circlepath", text: term, fill: true)
                            }
                        } header: {
                            HStack {
                                SectionLabel("Recent")
                                Spacer()
                                Button("Clear") { youtube.clearRecentSearches() }
                                    .font(Theme.ui(12, weight: .semibold))
                                    .foregroundStyle(Theme.gold)
                            }
                        }
                    }
                } else {
                    Section {
                        row(symbol: "magnifyingglass", text: query.trimmingCharacters(in: .whitespaces), fill: false)
                        ForEach(suggestions, id: \.self) { term in
                            row(symbol: "magnifyingglass", text: term, fill: true)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear { focused = true }
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { suggestions = []; return }
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let result = await YouTubeSuggestions.fetch(trimmed)
            if !Task.isCancelled { suggestions = result }
        }
    }

    private func row(symbol: String, text: String, fill: Bool) -> some View {
        HStack(spacing: 14) {
            Button { youtube.search(text) } label: {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.goldGradientVertical)
                        .frame(width: 24)
                    Text(text)
                        .font(Theme.ui(16))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if fill {
                Button { query = text } label: {
                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(IconPressStyle())
            }
        }
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.hairline)
    }
}
