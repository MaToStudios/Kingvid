import SwiftUI
import WebKit

/// One web view with its state. Owns a long-lived WKWebView so playback survives tab switches.
/// Generic tabs live in the Browser; the YouTube experience owns two more (browse + player).
@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    enum Kind {
        case generic
        case youtubeBrowse
        case youtubePlayer
    }

    let id = UUID()
    let webView: WKWebView
    let isPrivate: Bool
    let kind: Kind
    weak var store: BrowserStore?

    // Hooks used by the YouTube experience.
    var onWatchRequest: ((URL) -> Void)?
    var onOpenExternal: ((URL) -> Void)?
    var onURLChange: ((URL?) -> Void)?

    @Published var title = ""
    @Published var url: URL?
    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isSecure = false
    @Published var snapshot: UIImage?
    @Published var desktopMode: Bool
    /// True while the SwiftUI start page should cover the web view.
    @Published var showsHome: Bool

    private let messageProxy: ScriptMessageProxy
    private var observers: [NSKeyValueObservation] = []
    private var pendingURL: URL?
    private var historyTask: Task<Void, Never>?
    private var lastHistoryURL: URL?

    init(url: URL?, isPrivate: Bool, kind: Kind = .generic, store: BrowserStore) {
        let proxy = ScriptMessageProxy()
        let webView = WKWebView(frame: .zero,
                                configuration: WebViewFactory.makeConfiguration(kind: kind, isPrivate: isPrivate, handler: proxy))
        self.webView = webView
        self.isPrivate = isPrivate
        self.kind = kind
        self.store = store
        self.messageProxy = proxy
        self.pendingURL = url
        self.url = url
        self.showsHome = (url == nil && kind == .generic)
        self.desktopMode = Prefs.desktopMode && kind == .generic
        super.init()

        proxy.target = self
        WebViewFactory.style(webView, kind: kind)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        installObservers()

        // Pull-to-refresh only on ordinary pages. On video pages a stray downward drag at the top would
        // reload the page and restart the video, so YouTube views never get it.
        if kind == .generic {
            let refresh = UIRefreshControl()
            refresh.tintColor = UIColor(Theme.gold)
            refresh.addTarget(self, action: #selector(pulledToRefresh(_:)), for: .valueChanged)
            webView.scrollView.refreshControl = refresh
        }
    }

    // MARK: Navigation API

    var canGoBackEffective: Bool { canGoBack || (showsHome && webView.url != nil) }

    func load(_ url: URL) {
        pendingURL = nil
        showsHome = false
        self.url = url
        webView.load(URLRequest(url: url))
    }

    /// Loads an in-memory page (used by the playback test page).
    func loadHTML(_ html: String, title: String) {
        pendingURL = nil
        showsHome = false
        self.title = title
        webView.loadHTMLString(html, baseURL: URL(string: "https://kingvid.test/"))
    }

    /// Restored tabs load lazily, the first time they are shown.
    func ensureLoaded() {
        guard let pending = pendingURL else { return }
        pendingURL = nil
        webView.load(URLRequest(url: pending))
    }

    func goBack() {
        if showsHome && webView.url != nil {
            showsHome = false
        } else {
            webView.goBack()
        }
    }

    func goForward() { webView.goForward() }

    func goHome() { showsHome = true }

    func reloadOrStop() {
        if isLoading {
            webView.stopLoading()
        } else if webView.url == nil, let url {
            load(url)
        } else {
            webView.reload()
        }
    }

    func toggleDesktopMode() {
        desktopMode.toggle()
        if webView.url != nil { webView.reload() }
    }

    @objc private func pulledToRefresh(_ sender: UIRefreshControl) {
        webView.reload()
        sender.endRefreshing()
    }

    func captureSnapshot() {
        guard !showsHome, webView.window != nil else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 420
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            Task { @MainActor in
                if let image { self?.snapshot = image }
            }
        }
    }

    /// Runs a call on the injected `window.__kv` helper, optionally inside a specific frame.
    func runKV(_ call: String, frame: WKFrameInfo? = nil) {
        webView.evaluateJavaScript("window.__kv && window.__kv.\(call)", in: frame, in: .page) { _ in }
    }

    func teardown() {
        historyTask?.cancel()
        observers.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.loadHTMLString("", baseURL: nil)
    }

    // MARK: State sync

    private func installObservers() {
        func add<V>(_ keyPath: KeyPath<WKWebView, V>) {
            observers.append(webView.observe(keyPath, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.syncState() }
            })
        }
        add(\.estimatedProgress)
        add(\.title)
        add(\.url)
        add(\.canGoBack)
        add(\.canGoForward)
        add(\.isLoading)
        add(\.hasOnlySecureContent)
    }

    func syncState() {
        if pendingURL == nil, url != webView.url { url = webView.url }
        let newTitle = webView.title ?? ""
        if title != newTitle, !newTitle.isEmpty || webView.url == nil { title = newTitle }
        if progress != webView.estimatedProgress { progress = webView.estimatedProgress }
        if isLoading != webView.isLoading { isLoading = webView.isLoading }
        if canGoBack != webView.canGoBack { canGoBack = webView.canGoBack }
        if canGoForward != webView.canGoForward { canGoForward = webView.canGoForward }
        if isSecure != webView.hasOnlySecureContent { isSecure = webView.hasOnlySecureContent }

        if let current = webView.url, current != lastHistoryURL {
            lastHistoryURL = current
            store?.persistSession()
            scheduleHistoryRecord()
            onURLChange?(current)
        }
    }

    /// Debounced so redirects and single-page-app navigations record one entry with the final title.
    private func scheduleHistoryRecord() {
        historyTask?.cancel()
        historyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.recordHistory()
        }
    }

    private func recordHistory() {
        guard !isPrivate, let url = webView.url,
              let scheme = url.scheme, scheme == "http" || scheme == "https" else { return }
        store?.library.recordVisit(title: webView.title ?? "", url: url)
    }

    private func handleFailure(_ error: Error) {
        let nsError = error as NSError
        DiagnosticsLog.shared.add("nav", "load failed: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
        guard nsError.domain == NSURLErrorDomain, nsError.code != NSURLErrorCancelled else { return }
        let failing = (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? webView.url?.absoluteString ?? ""
        let html = ErrorPage.html(message: nsError.localizedDescription, url: failing)
        webView.loadHTMLString(html, baseURL: URL(string: failing))
    }
}

// MARK: - WKNavigationDelegate

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel, preferences)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "data", "blob", "file", "javascript"].contains(scheme) else {
            // Don't bounce into other apps (youtube://, itms-apps://, ...); only allow basic system schemes.
            if ["tel", "mailto", "sms", "facetime"].contains(scheme) {
                UIApplication.shared.open(url)
            } else {
                DiagnosticsLog.shared.add("nav", "blocked scheme \(scheme):// from \(self.webView.url?.host ?? "?")")
            }
            decisionHandler(.cancel, preferences)
            return
        }

        if kind == .youtubeBrowse, navigationAction.targetFrame?.isMainFrame == true {
            // A real (non-SPA) navigation to a video opens it in the dedicated player view.
            if YouTubeURL.isWatch(url) {
                onWatchRequest?(url)
                decisionHandler(.cancel, preferences)
                return
            }
            // Tapped links that leave YouTube/Google open in the Browser tab instead.
            if navigationAction.navigationType == .linkActivated, !YouTubeURL.isInternalHost(url) {
                onOpenExternal?(url)
                decisionHandler(.cancel, preferences)
                return
            }
        }

        preferences.preferredContentMode = desktopMode ? .desktop : .mobile
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            DiagnosticsLog.shared.add("nav", "cannot display \(navigationResponse.response.mimeType ?? "unknown type") (download not supported)")
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        showsHome = false
        // A full page load destroys the media element that was playing in this tab.
        store?.media.tabNavigated(id)
        syncState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        DiagnosticsLog.shared.add("nav", "web content process terminated; reloading")
        webView.reload()
    }
}

// MARK: - WKUIDelegate

extension BrowserTab: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if Prefs.blockPopups && navigationAction.navigationType == .other { return nil }
        guard let url = navigationAction.request.url, url.scheme?.hasPrefix("http") == true else { return nil }
        if kind == .generic {
            store?.openInNewTab(url, isPrivate: isPrivate)
        } else if YouTubeURL.isWatch(url) {
            onWatchRequest?(url)
        } else {
            onOpenExternal?(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        Alerts.alert(title: frame.request.url?.host ?? "", message: message, completion: completionHandler)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        Alerts.confirm(title: frame.request.url?.host ?? "", message: message, completion: completionHandler)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        Alerts.prompt(title: frame.request.url?.host ?? "", message: prompt,
                      defaultText: defaultText, completion: completionHandler)
    }

    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }
}

// MARK: - Script messages (media bridge + YouTube link interception)

extension BrowserTab: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch message.name {
        case "kvNav":
            if (body["type"] as? String) == "watch",
               let string = body["url"] as? String, let url = URL(string: string) {
                onWatchRequest?(url)
            }
        default:
            store?.media.handle(body, from: self, frame: message.frameInfo)
        }
    }
}
