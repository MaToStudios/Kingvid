import Foundation

/// JavaScript injected into every frame of every page (document start).
///
/// KingVid keeps the website's *original* player running. The script does four things:
///
/// 1. Page Visibility spoofing – makes `document.hidden` / `visibilityState` always report
///    "visible" and swallows `visibilitychange`/`blur`, so sites that auto-pause when the page is
///    hidden (YouTube, Dailymotion, ...) keep playing when the app is backgrounded or the screen locks.
/// 2. Auto-resume – if the system/WebKit pauses the active media element while the app is in the
///    background and the user did not ask for it, playback is resumed (with a watchdog timer).
/// 3. State bridge – posts play/pause/time/metadata (including `navigator.mediaSession`) to
///    native code (`kvMedia` message handler) which drives Now Playing, the mini-player and PiP.
/// 4. Command API – `window.__kv.cmd(name, arg)` lets native code play, pause, seek, change
///    speed, toggle Picture-in-Picture and trigger the site's next/previous handlers.
enum MediaScripts {
    static func bridge(spoofVisibility: Bool, autoResume: Bool) -> String {
        "window.__KV_OPTS = {spoof: \(spoofVisibility), resume: \(autoResume)};\n" + body
    }

    private static let body = #"""
    (function () {
      'use strict';
      if (window.__kv) { return; }
      var OPTS = window.__KV_OPTS || { spoof: true, resume: true };
      var kv = {
        bg: false,            // app is in background / screen locked
        userPause: false,     // last pause was requested by the user (lock screen, mini-player, PiP)
        wasPlaying: false,    // media was playing before the app went to background
        lastUser: 0,
        handlers: {},         // navigator.mediaSession action handlers registered by the site
        active: null,         // the media element we report on
        lastPost: 0
      };
      try {
        Object.defineProperty(window, '__kv', { value: kv, enumerable: false, configurable: false, writable: false });
      } catch (e) { window.__kv = kv; }

      // ---------------------------------------------------------------- 1. visibility spoofing
      if (OPTS.spoof) {
        try {
          var vis = { hidden: false, webkitHidden: false, visibilityState: 'visible', webkitVisibilityState: 'visible' };
          Object.keys(vis).forEach(function (k) {
            var def = { configurable: true, enumerable: true, get: function () { return vis[k]; } };
            try { Object.defineProperty(Document.prototype, k, def); } catch (e) {}
            try { Object.defineProperty(document, k, def); } catch (e) {}
          });
          Document.prototype.hasFocus = function () { return true; };
        } catch (e) {}
        var stop = function (e) { e.stopImmediatePropagation(); };
        ['visibilitychange', 'webkitvisibilitychange'].forEach(function (name) {
          window.addEventListener(name, stop, true);
          document.addEventListener(name, stop, true);
        });
        window.addEventListener('blur', function (e) {
          if (e.target === window || e.target === document) { e.stopImmediatePropagation(); }
        }, true);
      }

      // ---------------------------------------------------------------- helpers
      function isMedia(n) { return !!n && (n.tagName === 'VIDEO' || n.tagName === 'AUDIO'); }
      function absURL(u) { try { return new URL(u, location.href).href; } catch (e) { return ''; } }
      function playSafe(el) {
        try { var p = el.play(); if (p && p.catch) { p.catch(function () {}); } } catch (e) {}
      }
      function pick() {
        var list = document.querySelectorAll('video,audio');
        var best = null;
        for (var i = 0; i < list.length; i++) {
          var el = list[i];
          if (!el.paused && !el.ended) { return el; }
          if (!best || (el.duration || 0) > (best.duration || 0)) { best = el; }
        }
        return best;
      }
      function metadata() {
        try { return navigator.mediaSession && navigator.mediaSession.metadata; } catch (e) { return null; }
      }
      function bestArtwork() {
        try {
          var md = metadata();
          if (md && md.artwork && md.artwork.length) {
            var best = null, bestSize = -1;
            for (var i = 0; i < md.artwork.length; i++) {
              var a = md.artwork[i], sz = 0;
              if (a.sizes) { var m = /(\d+)x(\d+)/.exec(a.sizes); if (m) { sz = parseInt(m[1], 10); } }
              if (sz >= bestSize) { best = a; bestSize = sz; }
            }
            if (best && best.src) { return absURL(best.src); }
          }
        } catch (e) {}
        try {
          if (/youtube\./.test(location.hostname)) {
            var yt = /[?&]v=([\w-]{6,})/.exec(location.search);
            if (yt) { return 'https://i.ytimg.com/vi/' + yt[1] + '/hqdefault.jpg'; }
          }
          var og = document.querySelector('meta[property="og:image"],meta[name="twitter:image"]');
          if (og && og.content) { return absURL(og.content); }
        } catch (e) {}
        return '';
      }

      // ---------------------------------------------------------------- 3. state bridge
      function post(el, force) {
        if (!el) { return; }
        var now = Date.now();
        if (!force && now - kv.lastPost < 900) { return; }
        kv.lastPost = now;
        var md = metadata();
        var dur = el.duration;
        var msg = {
          type: 'state',
          paused: !!el.paused,
          ended: !!el.ended,
          duration: isFinite(dur) ? dur : 0,
          live: dur === Infinity,
          position: isFinite(el.currentTime) ? el.currentTime : 0,
          rate: el.playbackRate || 1,
          title: (md && md.title) || document.title || location.hostname,
          artist: (md && (md.artist || md.album)) || location.hostname,
          artwork: bestArtwork(),
          isVideo: el.tagName === 'VIDEO' && el.videoWidth > 0,
          pip: el.webkitPresentationMode === 'picture-in-picture',
          hasNext: !!kv.handlers.nexttrack,
          hasPrev: !!kv.handlers.previoustrack,
          url: location.href,
          host: location.hostname
        };
        try { window.webkit.messageHandlers.kvMedia.postMessage(msg); } catch (e) {}
      }

      // ---------------------------------------------------------------- 2. auto-resume
      function onPause(el) {
        var inPip = el.webkitPresentationMode === 'picture-in-picture';
        var userish = kv.userPause || inPip || el.ended || (Date.now() - kv.lastUser < 1500);
        if (kv.bg && OPTS.resume && !userish && kv.wasPlaying) {
          // The page or WebKit paused us while backgrounded: resume without telling the UI.
          setTimeout(function () {
            if (kv.bg && el.paused && !kv.userPause && !el.ended) { playSafe(el); }
          }, 120);
          setTimeout(function () { if (el.paused) { post(el, true); } }, 1500);
          return;
        }
        kv.wasPlaying = false;
        post(el, true);
      }

      var EVENTS = ['play', 'playing', 'pause', 'ended', 'loadedmetadata', 'durationchange',
                    'ratechange', 'seeked', 'timeupdate', 'webkitpresentationmodechanged', 'error'];

      function eligible(el) {
        // ignore muted decorative / preview videos unless they are already the active element
        if (el === kv.active) { return true; }
        if (el.muted || el.volume === 0) { return false; }
        return true;
      }

      // Media failures never reach the UI otherwise; report them so the app can show/log the real cause.
      function postError(el) {
        var err = el.error || {};
        var msg = {
          type: 'mediaError', code: err.code || 0, message: String(err.message || '').slice(0, 200),
          src: String(el.currentSrc || el.src || '').slice(0, 200),
          networkState: el.networkState, readyState: el.readyState, host: location.hostname
        };
        try { window.webkit.messageHandlers.kvMedia.postMessage(msg); } catch (e) {}
      }

      function onEvt(e) {
        var el = e.target;
        if (!isMedia(el)) { return; }
        var t = e.type;
        if (t === 'error') { postError(el); return; }
        if (t === 'play' || t === 'playing') {
          if (!eligible(el)) { return; }
          kv.active = el;
          if (t === 'playing') { kv.wasPlaying = true; kv.userPause = false; }
        }
        if (el !== kv.active) { return; }
        if (t === 'pause') { onPause(el); return; }
        if (t === 'ended') { kv.wasPlaying = false; }
        post(el, t !== 'timeupdate');
      }

      EVENTS.forEach(function (ev) { document.addEventListener(ev, onEvt, true); });

      // Detached `new Audio()` elements never reach document capture listeners: track them on play().
      function track(el) {
        if (el.__kvT) { return; }
        el.__kvT = true;
        if (el.isConnected) { return; }
        EVENTS.forEach(function (ev) { el.addEventListener(ev, onEvt, false); });
      }
      try {
        var origPlay = HTMLMediaElement.prototype.play;
        HTMLMediaElement.prototype.play = function () {
          try { track(this); } catch (e) {}
          return origPlay.apply(this, arguments);
        };
      } catch (e) {}

      // Capture the site's media-session handlers so native next/previous can invoke them.
      try {
        var MS = window.MediaSession && window.MediaSession.prototype;
        if (MS && MS.setActionHandler) {
          var origSet = MS.setActionHandler;
          MS.setActionHandler = function (action, handler) {
            kv.handlers[action] = handler;
            return origSet.apply(this, arguments);
          };
        }
      } catch (e) {}

      // One-time capability report for the diagnostics screen (top frame only).
      if (window === window.top) {
        try {
          var probe = document.createElement('video');
          window.webkit.messageHandlers.kvMedia.postMessage({
            type: 'diag', host: location.hostname,
            mse: typeof window.MediaSource, mms: typeof window.ManagedMediaSource,
            hls: probe.canPlayType('application/vnd.apple.mpegurl') || 'no',
            mp4: probe.canPlayType('video/mp4; codecs="avc1.42E01E, mp4a.40.2"') || 'no',
            webm: probe.canPlayType('video/webm; codecs="vp9"') || 'no'
          });
        } catch (e) {}
      }

      // ---------------------------------------------------------------- 4. command API
      kv.cmd = function (name, arg) {
        var el = kv.active || pick();
        if (!el) { return false; }
        switch (name) {
          case 'play':
            kv.userPause = false; kv.wasPlaying = true; playSafe(el); break;
          case 'pause':
            kv.userPause = true; kv.wasPlaying = false; kv.lastUser = Date.now();
            try { el.pause(); } catch (e) {} break;
          case 'hold':        // audio interruption (call, Siri): WebKit pauses by itself; we only stop auto-resume
            kv.userPause = true; kv.lastUser = Date.now(); break;
          case 'seek':
            try { el.currentTime = Math.max(0, arg); } catch (e) {} break;
          case 'skip':
            try {
              var dur = isFinite(el.duration) ? el.duration : 1e9;
              el.currentTime = Math.max(0, Math.min(dur, el.currentTime + arg));
            } catch (e) {} break;
          case 'rate':
            try { el.playbackRate = arg; } catch (e) {} break;
          case 'pip':
          case 'pipOn':
          case 'pipOff':
            try {
              if (el.webkitSupportsPresentationMode && el.webkitSupportsPresentationMode('picture-in-picture')) {
                var inPip = el.webkitPresentationMode === 'picture-in-picture';
                var want = name === 'pipOn' ? true : (name === 'pipOff' ? false : !inPip);
                if (want !== inPip) { el.webkitSetPresentationMode(want ? 'picture-in-picture' : 'inline'); }
              }
            } catch (e) {} break;
          case 'next':
            if (kv.handlers.nexttrack) { try { kv.handlers.nexttrack({ action: 'nexttrack' }); } catch (e) {} } break;
          case 'prev':
            if (kv.handlers.previoustrack) { try { kv.handlers.previoustrack({ action: 'previoustrack' }); } catch (e) {} } break;
        }
        post(el, true);
        return true;
      };

      kv.report = function () { post(kv.active || pick(), true); };

      // Native tells us when the app moves between foreground and background; forward to child frames.
      kv.setBg = function (flag) {
        flag = !!flag;
        kv.bg = flag;
        if (flag) {
          if (kv.active && !kv.active.paused) { kv.wasPlaying = true; }
          [400, 1200, 3000].forEach(function (ms) { setTimeout(kv.resume, ms); });
        } else {
          kv.wasPlaying = !!(kv.active && !kv.active.paused);
        }
        try {
          for (var i = 0; i < window.frames.length; i++) {
            try { window.frames[i].postMessage({ __kvBg: flag }, '*'); } catch (e) {}
          }
        } catch (e) {}
      };
      window.addEventListener('message', function (e) {
        var d = e.data;
        if (d && typeof d === 'object' && d.__kvBg !== undefined && e.source === window.parent) { kv.setBg(d.__kvBg); }
      }, false);

      kv.resume = function () {
        if (!kv.bg || kv.userPause || !kv.wasPlaying || !OPTS.resume) { return; }
        var el = kv.active;
        if (el && el.paused && !el.ended) { playSafe(el); }
      };

      // Watchdog while backgrounded + auto-confirm "Are you still watching?" prompts.
      setInterval(function () {
        if (!kv.bg) { return; }
        kv.resume();
        try {
          var b = document.querySelector(
            'yt-confirm-dialog-renderer #confirm-button button, yt-confirm-dialog-renderer #confirm-button, ' +
            'ytmusic-you-there-renderer button, ytmusic-you-there-renderer #button');
          if (b) { b.click(); }
        } catch (e) {}
      }, 2000);
    })();
    """#
}
