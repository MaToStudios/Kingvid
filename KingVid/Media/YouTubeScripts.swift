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
        // ---- Video-only layout. KingVid draws the watch screen natively (details, up next) and one control
        // overlay, so this web view shows nothing but the real YouTube video, filling the view edge to edge.
        // Selectors match m.youtube.com's real structure: body > #player-container-id > #player > #movie_player
        // > .html5-video-container > video.html5-main-video.
        var vcss = 'html,body{background:#000!important;overflow:hidden!important;margin:0!important}' +
          'body>*:not(#player-container-id){visibility:hidden!important}' +
          '#player-container-id{position:fixed!important;top:0!important;left:0!important;right:0!important;bottom:0!important;' +
            'width:100vw!important;height:100vh!important;max-height:none!important;margin:0!important;padding:0!important;' +
            'z-index:2147483000!important;background:#000!important;transform:none!important;visibility:visible!important}' +
          '#player-container-id #player,#player-container-id #movie_player,#player-container-id .html5-video-container{' +
            'position:absolute!important;top:0!important;left:0!important;width:100%!important;height:100%!important;' +
            'padding:0!important;margin:0!important;transform:none!important;max-height:none!important}' +
          '#player-container-id video{position:absolute!important;top:0!important;left:0!important;width:100%!important;' +
            'height:100%!important;object-fit:contain!important;background:#000!important;transform:none!important}' +
          // YouTube's own control layer: KingVid's single native overlay replaces it (no competing controls).
          'ytm-watch-player-controls,ytm-custom-control,.player-controls-content,.player-controls-background,' +
          '.player-controls-top,.player-controls-middle,.player-controls-bottom,.ytp-chrome-bottom,.ytp-chrome-top,' +
          '.ytp-gradient-bottom,.ytp-gradient-top,.ytp-large-play-button,.ytp-pause-overlay,.ytp-ce-element,' +
          '.ytp-cards-teaser,.ytp-paid-content-overlay,.ytp-endscreen-content,.ytp-autonav-endscreen-countdown-overlay,' +
          '.ytp-unmute,.ytm-autonav-bar{display:none!important}';
        (function injectVideoOnly() {
          if (document.getElementById('kv-yt-video')) { return; }
          var root = document.head || document.documentElement;
          if (!root) { return; }
          var st = document.createElement('style');
          st.id = 'kv-yt-video';
          st.textContent = vcss;
          root.appendChild(st);
        })();
        document.addEventListener('DOMContentLoaded', function () {
          if (!document.getElementById('kv-yt-video')) {
            var st = document.createElement('style'); st.id = 'kv-yt-video'; st.textContent = vcss;
            (document.head || document.documentElement).appendChild(st);
          }
        });

        // ---- Page data for the native watch screen (title, channel, description, up next).
        function currentVideoId() {
          var m = /[?&]v=([\w-]{6,})/.exec(location.search);
          if (m) { return m[1]; }
          m = /^\/(shorts|live)\/([\w-]{6,})/.exec(location.pathname);
          return m ? m[2] : null;
        }
        var postedFor = null;
        function postWatchData() {
          var id = currentVideoId();
          if (!id || postedFor === id) { return; }
          var pr = window.ytInitialPlayerResponse;
          var vd = pr && pr.videoDetails;
          // After in-page navigation the embedded data is stale; native code fetches it instead.
          if (!vd || vd.videoId !== id) { return; }
          postedFor = id;
          var initial = null;
          try { initial = JSON.stringify(window.ytInitialData || null); } catch (err) {}
          post({
            type: 'watchData', videoId: id,
            playerResponse: JSON.stringify({ videoDetails: pr.videoDetails, microformat: pr.microformat }),
            initialData: initial
          });
        }
        document.addEventListener('DOMContentLoaded', postWatchData);
        window.addEventListener('load', postWatchData);
        var dataTries = 0;
        var dataTimer = setInterval(function () { postWatchData(); if (++dataTries > 20) { clearInterval(dataTimer); } }, 1000);

        // Autoplay helper: only until the video has actually started once, the user touches the page,
        // or the user paused from KingVid's native controls. It must never fight a deliberate pause.
        var stopped = false;
        function stopHelper() { stopped = true; }
        ['touchstart', 'pointerdown', 'mousedown'].forEach(function (n) {
          document.addEventListener(n, stopHelper, true);
        });
        document.addEventListener('playing', function (e) {
          if (e.target && e.target.tagName === 'VIDEO') { stopHelper(); }
        }, true);
        var tries = 0;
        var iv = setInterval(function () {
          tries++;
          var userPaused = window.__kv && window.__kv.userPause;
          var v = document.querySelector('video');
          if (!stopped && !userPaused && v && v.paused && !v.ended && v.readyState >= 2) {
            try { var p = v.play(); if (p && p.catch) { p.catch(function () {}); } } catch (err) {}
          }
          if (tries > 24 || stopped || userPaused) { clearInterval(iv); }
        }, 500);
      }
    })();
    """#
}
