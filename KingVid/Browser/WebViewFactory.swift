import SwiftUI
import WebKit

/// WKScriptMessageHandler retains its handler strongly; this proxy breaks the
/// BrowserTab -> WKWebView -> configuration -> handler -> BrowserTab cycle.
@MainActor
final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
enum WebViewFactory {
    /// Safari-style user agent suffix using the *real* OS version. Google sign-in and many players refuse
    /// embedded-WebView user agents (no "Safari/" token) and are suspicious of mismatched versions.
    static var userAgentSuffix: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "Version/\(v.majorVersion).\(v.minorVersion) Mobile/15E148 Safari/604.1"
    }

    static func makeConfiguration(kind: BrowserTab.Kind, isPrivate: Bool,
                                  handler: WKScriptMessageHandler) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()

        // Media: inline playback, no user-gesture requirement, PiP + AirPlay allowed.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        // Without this, the HTML Fullscreen API (Vimeo, Dailymotion, Twitch, ...) silently does nothing on iPhone.
        config.preferences.isElementFullscreenEnabled = true

        config.websiteDataStore = isPrivate ? WKWebsiteDataStore.nonPersistent() : WKWebsiteDataStore.default()
        config.applicationNameForUserAgent = userAgentSuffix
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences.preferredContentMode = Prefs.desktopMode && kind == .generic ? .desktop : .mobile

        let controller = WKUserContentController()
        for script in userScripts(kind: kind) { controller.addUserScript(script) }
        controller.add(handler, name: "kvMedia")
        controller.add(handler, name: "kvNav")
        config.userContentController = controller
        return config
    }

    static func userScripts(kind: BrowserTab.Kind) -> [WKUserScript] {
        var scripts = [
            WKUserScript(source: MediaScripts.bridge(spoofVisibility: Prefs.spoofVisibility,
                                                     autoResume: Prefs.autoResume),
                         injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ]
        switch kind {
        case .generic:
            break
        case .youtubeBrowse, .youtubePlayer:
            let role = kind == .youtubeBrowse ? "browse" : "player"
            scripts.append(WKUserScript(source: YouTubeScripts.script(role: role, hideChrome: Prefs.ytHideChrome),
                                        injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        return scripts
    }

    /// Changes whenever a setting that affects the injected scripts changes.
    static var scriptSignature: String {
        "\(Prefs.spoofVisibility)-\(Prefs.autoResume)-\(Prefs.ytHideChrome)"
    }

    static func style(_ webView: WKWebView, kind: BrowserTab.Kind) {
        let bg = UIColor(Theme.background)
        webView.allowsBackForwardNavigationGestures = kind == .generic
        webView.allowsLinkPreview = kind == .generic
        webView.isOpaque = false
        webView.backgroundColor = bg
        webView.scrollView.backgroundColor = bg
        webView.underPageBackgroundColor = bg
        webView.isInspectable = true
        if kind != .generic {
            // Makes `prefers-color-scheme: dark` true so YouTube renders its dark theme.
            webView.overrideUserInterfaceStyle = .dark
        }
    }
}

/// Hosts a tab's long-lived WKWebView inside SwiftUI.
struct WebViewRepresentable: UIViewRepresentable {
    let tab: BrowserTab

    func makeUIView(context: Context) -> WKWebView { tab.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

enum ErrorPage {
    static func html(message: String, url: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
        background:#060607;color:#f5f0e4;font-family:-apple-system,Helvetica,sans-serif;text-align:center}
        .box{max-width:340px;padding:28px}
        h1{font-family:ui-serif,Georgia,serif;font-size:24px;margin:0 0 10px;
        background:linear-gradient(135deg,#fbefb0,#d9b13f,#8f6a14);-webkit-background-clip:text;color:transparent}
        p{color:#a29c8e;line-height:1.45;font-size:15px;margin:0 0 6px;word-break:break-word}
        a.btn{display:inline-block;margin-top:22px;padding:12px 28px;border-radius:999px;color:#1a1305;
        font-weight:600;text-decoration:none;background:linear-gradient(135deg,#fbefb0,#d9b13f,#8f6a14)}
        </style></head><body><div class="box">
        <h1>Can't open this page</h1>
        <p>\(esc(message))</p><p>\(esc(url))</p>
        <a class="btn" href="\(esc(url))">Try Again</a>
        </div></body></html>
        """
    }
}
