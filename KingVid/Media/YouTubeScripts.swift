import Foundation

/// Script injected into the two YouTube web views (browse + player). It only runs on m./www.youtube.com.
///
/// * role "browse": taps on videos are intercepted (capture phase, before YouTube's own router) and sent
///   to native code (`kvNav`), which opens the video in the dedicated player web view. That is what lets
///   a video keep playing (mini-player) while you keep browsing.
/// * role "player": attempts autoplay a few times until the user touches the page.
/// * both: optionally hides YouTube's own top/bottom bars because KingVid draws native ones.
///
/// Nothing here touches the original YouTube player: no stream extraction, no element replacement.
enum YouTubeScripts {
    static func script(role: String, hideChrome: Bool) -> String {
        "window.__KV_YT = {role: '\(role)', hideChrome: \(hideChrome)};\n" + body
    }

    private static let body = #"""
    (function () {
      'use strict';
      if (!/^(m|www)\.youtube\.com$/.test(location.hostname)) { return; }
      if (window.__kvYT) { return; }
      window.__kvYT = true;
      var cfg = window.__KV_YT || { role: 'browse', hideChrome: true };

      function post(msg) {
        try { window.webkit.messageHandlers.kvNav.postMessage(msg); } catch (e) {}
      }

      // ---------------------------------------------------------------- styling
      var css = 'html,body{overscroll-behavior-y:none!important}';
      css += 'ytm-mealbar-promo-renderer,ytm-app-promo-bar,.mobile-topbar-header-open-app{display:none!important}';
      if (cfg.hideChrome) {
        css += 'ytm-pivot-bar-renderer{display:none!important}';
        css += 'header.mobile-topbar-header,ytm-mobile-topbar-renderer{display:none!important}';
      }
      function injectCSS() {
        if (document.getElementById('kv-yt-style')) { return; }
        var root = document.head || document.documentElement;
        if (!root) { return; }
        var st = document.createElement('style');
        st.id = 'kv-yt-style';
        st.textContent = css;
        root.appendChild(st);
      }
      injectCSS();
      document.addEventListener('DOMContentLoaded', injectCSS);

      // ---------------------------------------------------------------- browse role
      if (cfg.role === 'browse') {
        document.addEventListener('click', function (e) {
          var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
          if (!a) { return; }
          var u;
          try { u = new URL(a.href, location.href); } catch (err) { return; }
          var yt = /(^|\.)youtube\.com$/.test(u.hostname);
          var short = u.hostname === 'youtu.be' && u.pathname.length > 1;
          var watch = yt && (u.pathname === '/watch' || u.pathname.indexOf('/shorts/') === 0 || u.pathname.indexOf('/live/') === 0);
          if (watch || short) {
            e.preventDefault();
            e.stopImmediatePropagation();
            post({ type: 'watch', url: u.href });
          }
        }, true);

        // Safety net: if a video starts audibly in the browse view anyway, move it to the player view.
        document.addEventListener('playing', function (e) {
          var v = e.target;
          if (v && v.tagName === 'VIDEO' && !v.muted && /^\/(watch|shorts|live)/.test(location.pathname)) {
            try { v.pause(); } catch (err) {}
            post({ type: 'watch', url: location.href });
          }
        }, true);
      }

      // ---------------------------------------------------------------- player role
      if (cfg.role === 'player') {
        var touched = false;
        ['touchstart', 'pointerdown', 'mousedown'].forEach(function (n) {
          document.addEventListener(n, function () { touched = true; }, true);
        });
        var tries = 0;
        var iv = setInterval(function () {
          tries++;
          var v = document.querySelector('video');
          if (v && v.paused && !v.ended && !touched && v.readyState >= 2) {
            try { var p = v.play(); if (p && p.catch) { p.catch(function () {}); } } catch (err) {}
          }
          if (tries > 24 || touched) { clearInterval(iv); }
        }, 500);
      }
    })();
    """#
}
