import SwiftUI
import WebKit

@MainActor
final class BrowserStore: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published private(set) var selectedID: UUID?
    /// The tab that currently owns the media session. Its web view stays attached while hidden.
    @Published var mediaTabID: UUID?

    let media: MediaCenter
    let library: LibraryStore

    private let sessionKey = "session.tabs.v1"
    private var scriptSignature = WebViewFactory.scriptSignature

    private struct SessionData: Codable {
        var urls: [String]
        var selected: Int
    }

    init(media: MediaCenter, library: LibraryStore) {
        self.media = media
        self.library = library

        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshScriptsIfNeeded() }
        }
    }

    var selected: BrowserTab? { tabs.first { $0.id == selectedID } }

    func tab(withID id: UUID) -> BrowserTab? { tabs.first { $0.id == id } }

    // MARK: Lifecycle

    func start() {
        restoreSession()
        if tabs.isEmpty { newTab() }
    }

    @discardableResult
    func newTab(url: URL? = nil, isPrivate: Bool = false, select: Bool = true) -> BrowserTab {
        var target = url
        if target == nil, !isPrivate, !Prefs.homepage.isEmpty {
            target = URLResolver.resolve(Prefs.homepage)
        }
        let tab = BrowserTab(url: target, isPrivate: isPrivate, store: self)
        if target != nil { tab.ensureLoaded() }
        tabs.append(tab)
        if select { self.select(tab) } else { persistSession() }
        return tab
    }

    func openInNewTab(_ url: URL, isPrivate: Bool) {
        newTab(url: url, isPrivate: isPrivate, select: true)
    }

    func select(_ tab: BrowserTab) {
        selected?.captureSnapshot()
        selectedID = tab.id
        tab.ensureLoaded()
        persistSession()
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        media.tabClosed(tab.id)
        tab.teardown()
        tabs.remove(at: index)
        if tabs.isEmpty {
            newTab()
        } else if selectedID == tab.id {
            select(tabs[min(index, tabs.count - 1)])
        } else {
            persistSession()
        }
    }

    func closeAll() {
        for tab in tabs {
            media.tabClosed(tab.id)
            tab.teardown()
        }
        tabs.removeAll()
        selectedID = nil
        newTab()
    }

    // MARK: Navigation

    func navigate(_ input: String, in tab: BrowserTab? = nil) {
        guard let target = tab ?? selected, let url = URLResolver.resolve(input) else { return }
        target.load(url)
    }

    /// Opens a URL from the library / home screen in the current tab.
    func open(_ url: URL) {
        guard let tab = selected else { newTab(url: url); return }
        tab.load(url)
    }

    func showTab(withID id: UUID) {
        if let tab = tab(withID: id) { select(tab) }
    }

    // MARK: Session persistence

    func persistSession() {
        let normal = tabs.filter { !$0.isPrivate }
        let urls = normal.map { $0.url?.absoluteString ?? "" }
        let index = normal.firstIndex { $0.id == selectedID } ?? 0
        if let data = try? JSONEncoder().encode(SessionData(urls: urls, selected: index)) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(SessionData.self, from: data),
              !session.urls.isEmpty else { return }
        for raw in session.urls {
            let url = raw.isEmpty ? nil : URL(string: raw)
            tabs.append(BrowserTab(url: url, isPrivate: false, store: self))
        }
        let index = min(max(session.selected, 0), tabs.count - 1)
        select(tabs[index])
    }

    // MARK: Settings that affect the injected script

    private func refreshScriptsIfNeeded() {
        let signature = WebViewFactory.scriptSignature
        guard signature != scriptSignature else { return }
        scriptSignature = signature
        for tab in tabs {
            let controller = tab.webView.configuration.userContentController
            controller.removeAllUserScripts()
            controller.addUserScript(WebViewFactory.userScript())
        }
    }
}
