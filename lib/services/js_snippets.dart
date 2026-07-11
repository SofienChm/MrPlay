class JsSnippets {
  JsSnippets._();

  static const audioPauseBlocker = '''
(function() {
  if (window.__mrplayPlayOverrideInstalled) return;
  window.__mrplayPlayOverrideInstalled = true;
  if (!window.__mrplayOrigProtoPlay) {
    window.__mrplayOrigProtoPlay = HTMLVideoElement.prototype.play;
    HTMLVideoElement.prototype.play = function() {
      if (window.__mrplayUserPaused) return Promise.resolve();
      if (window.__mrplayExternallyPaused) return Promise.resolve();
      return window.__mrplayOrigProtoPlay.apply(this, arguments);
    };
  }
  var v = document.querySelector('video');
  if (v) {
    v.addEventListener('pause', function __mrplayOnPause() {
      window.__mrplayExternallyPaused = true;
      setTimeout(function() {
        window.__mrplayExternallyPaused = false;
      }, 3000);
    });
  }
})();
''';

  static const cleanupIntervals = '''
(function() {
  if (window.__mrplayKeepAliveInterval) clearInterval(window.__mrplayKeepAliveInterval);
  if (window.__mrplaySpoofInterval) clearInterval(window.__mrplaySpoofInterval);
  window.__mrplayKeepAlive = false;
  window.__mrplayKeepAliveInjected = false;
  window.__mrplayBgInjected = false;
  window.__mrplaySearchMonitorInjected = false;
  window.__mrplayViewportMonitorInjected = false;
  window.__mrplayMiniPlayerMonitorInjected = false;
  if (window.__mrplayMiniPlayerInterval) clearInterval(window.__mrplayMiniPlayerInterval);
  if (window.__mrplayUnmuteInterval) clearInterval(window.__mrplayUnmuteInterval);
})();
''';

  static const cleanupBgInterval = '''
(function() {
  if (window.__mrplayBgInterval) clearInterval(window.__mrplayBgInterval);
})();
''';

  static const keepAliveVisibilitySpoof = '''
(function() {
  if (window.__mrplayKeepAliveInjected) return;
  window.__mrplayKeepAliveInjected = true;

  function spoofVisibility() {
    try {
      Object.defineProperty(document, 'visibilityState', {
        get: function() { return 'visible'; },
        configurable: true
      });
      Object.defineProperty(document, 'hidden', {
        get: function() { return false; },
        configurable: true
      });
      // Intentionally NO mediaSession pause handler here —
      // let it fall through to MPRemoteCommandCenter on iOS
      // so native code can actually pause the video.
    } catch(e) {}
  }

  spoofVisibility();
  window.__mrplaySpoofInterval = setInterval(function() {
    if (!window.__mrplayUserPaused) spoofVisibility();
  }, 1000);

  var _addEventListener = document.addEventListener;
  document.addEventListener = function(type, listener, options) {
    if (type === 'visibilitychange') return;
    _addEventListener.call(this, type, listener, options);
  };
})();
''';

  static const unmuteVideo = '''
(function() {
  if (window.__mrplayUnmuteInjected) return;
  window.__mrplayUnmuteInjected = true;

  function tryPlayerApi() {
    try {
      var player = document.querySelector('ytm-player') ||
                   document.querySelector('ytm-watch');
      if (player && player.setVolume) player.setVolume(100);
      if (player && player.unmute) player.unmute();
      if (window.yt && window.yt.player) {
        var p = window.yt.player.getPlayerByElement
          ? window.yt.player.getPlayerByElement(document.querySelector('ytm-player'))
          : null;
        if (p) { p.unMute(); p.setVolume(100); }
      }
    } catch(e) { console.error('[MrPlay] playerApi:', e); }
  }

  function ensureUnmuted() {
    try {
      var video = document.querySelector('video');
      if (video) {
        video.muted = false;
        video.volume = 1.0;
        if (video.paused) video.play().catch(function(){});
      }
      var btns = document.querySelectorAll(
        'button[aria-label*="nmute" i], ' +
        'button[aria-label*="Unmute" i], ' +
        '.ytp-unmute, ' +
        'ytm-tap-to-unmute button, ' +
        '[class*="unmute"] button, ' +
        '[class*="unmute-button"]'
      );
      for (var i = 0; i < btns.length; i++) btns[i].click();
      tryPlayerApi();
      return !!(video && !video.muted && video.volume > 0.5);
    } catch(e) {
      console.error('[MrPlay] ensureUnmuted:', e);
      return false;
    }
  }

  ensureUnmuted();
  var attempts = 0;
  window.__mrplayUnmuteInterval = setInterval(function() {
    attempts++;
    if (ensureUnmuted() || attempts >= 15) {
      clearInterval(window.__mrplayUnmuteInterval);
      window.__mrplayUnmuteInterval = null;
    }
  }, 400);
})();
''';

  static const visibilitySpoof = '''
(function() {
  try {
    Object.defineProperty(document, 'visibilityState', { value: 'visible', writable: true });
    Object.defineProperty(document, 'hidden', { value: false, writable: true });
    document.dispatchEvent(new Event('visibilitychange'));
    window.__mrplayKeepAlive = true;
    if (!window.__mrplayUserPaused) {
      window.__mrplayUserPaused = false;
    }
    if (!window.__mrplayKeepAliveInterval) {
      window.__mrplayKeepAliveInterval = setInterval(function() {
        if (!window.__mrplayKeepAlive) {
          clearInterval(window.__mrplayKeepAliveInterval);
          window.__mrplayKeepAliveInterval = null;
          return;
        }
        if (window.__mrplayUserPaused) return;
        if (window.__mrplayExternallyPaused) return;
        var v = document.querySelector('video');
        if (v && v.paused) v.play().catch(function(){});
      }, 500);
    }
  } catch(e) { console.error(e); }
})();
''';

  static const pauseVideo = '''
(function() {
  window.__mrplayUserPaused = true;
  window.__mrplayExternallyPaused = false;
  if (window.__mrplaySpoofInterval) { clearInterval(window.__mrplaySpoofInterval); window.__mrplaySpoofInterval = null; }
  if (window.__mrplayKeepAliveInterval) { clearInterval(window.__mrplayKeepAliveInterval); window.__mrplayKeepAliveInterval = null; }
  if (window.__mrplayBgInterval) { clearInterval(window.__mrplayBgInterval); window.__mrplayBgInterval = null; }
  try {
    if (navigator.mediaSession) {
      navigator.mediaSession.setActionHandler('play', null);
      navigator.mediaSession.setActionHandler('pause', null);
    }
  } catch(e) {}
  if (!window.__mrplayOrigProtoPlay) {
    window.__mrplayOrigProtoPlay = HTMLVideoElement.prototype.play;
    HTMLVideoElement.prototype.play = function() {
      if (window.__mrplayUserPaused) return Promise.resolve();
      if (window.__mrplayExternallyPaused) return Promise.resolve();
      return window.__mrplayOrigProtoPlay.apply(this, arguments);
    };
  }
  var v = document.querySelector('video');
  if (v && !v.paused) v.pause();
})();
''';

  static const resumeVideo = '''
(function() {
  window.__mrplayUserPaused = false;
  window.__mrplayExternallyPaused = false;
  var v = document.querySelector('video');
  if (v && v.paused) v.play().catch(function(){});
})();
''';

  static const restoreVisibility = '''
(function() {
  window.__mrplayKeepAlive = false;
  if (window.__mrplayKeepAliveInterval) {
    clearInterval(window.__mrplayKeepAliveInterval);
    window.__mrplayKeepAliveInterval = null;
  }
  try {
    delete document.hidden;
    delete document.visibilityState;
  } catch(e) {}
})();
''';

  static const cleanLayoutCss = '''
(function() {
  var s = document.getElementById('mrplay-clean-layout-css') || document.createElement('style');
  s.id = 'mrplay-clean-layout-css';
  s.textContent = `
    .ad-container, .ad-banner, .ad-slot, .advertisement, .sponsored,
    .promoted-video, .video-ads, .ytp-ad-module, .ytp-ad-image-overlay,
    .ytp-ad-text-overlay, .ytp-ad-player-overlay, .ytp-ad-progress,
    .ytp-ad-skip-button, .ytp-ad-skip-button-modern, #masthead-ad,
    ytm-mealbar-promo-renderer, .vssom-privacy-banner, ytm-consent-bump-v2-renderer,
    ytm-consent-bump-lightbox, .glass-container, ytm-dialog-renderer,
    .modal-overlay, [class*="consent-bump"], [class*="dialog-overlay"] {
      display: none !important; opacity: 0 !important; pointer-events: none !important;
    }
    button.ytm-open-app-button, .open-app-button, [aria-label*="Open App" i],
    [aria-label*="Ouvrir" i], [aria-label*="ouvrir l'app" i],
    .header-open-app-button, ytm-app-banner-renderer,
    [class*="app-banner"], [class*="app-prompt"],
    a[href*="vnd.youtube"], a[href*="youtube://"] {
      display: none !important; opacity: 0 !important; pointer-events: none !important;
      width: 0 !important; height: 0 !important;
    }
    ytm-tap-to-unmute, [class*="tap-to-unmute"], [class*="unmute-overlay"],
    [class*="unmute-button"], [class*="unmute-text"] {
      display: none !important; opacity: 0 !important; pointer-events: none !important;
    }
  `;
  if (!s.parentNode) document.head.appendChild(s);
})();
''';

  static const searchFocusMonitor = '''
(function() {
  if (window.__searchMonitorInjected) return;
  window.__searchMonitorInjected = true;
  function setup() {
    var input = document.querySelector('input.search-query') ||
                document.querySelector('input[aria-label="Search"]') ||
                document.querySelector('#search-input input');
    if (!input) return false;
    input.addEventListener('focus', function() {
      window.flutter_inappwebview.callHandler('searchFocusChanged', true);
    });
    input.addEventListener('blur', function() {
      window.flutter_inappwebview.callHandler('searchFocusChanged', false);
    });
    return true;
  }
  if (!setup()) {
    var obs = new MutationObserver(function() { if (setup()) obs.disconnect(); });
    obs.observe(document.body, { childList: true, subtree: true });
  }
})();
''';

  static const keyboardMonitor = '''
(function() {
  if (window.__viewportMonitorInjected) return;
  window.__viewportMonitorInjected = true;
  var h = window.innerHeight;
  window.visualViewport.addEventListener('resize', function() {
    window.flutter_inappwebview.callHandler(
      'keyboardOpenChanged', window.visualViewport.height < h * 0.75);
  });
})();
''';

  static const miniPlayerMonitor = '''
(function() {
  if (window.__miniPlayerMonitorInjected) return;
  window.__miniPlayerMonitorInjected = true;
  var _lastState = false;
  function check() {
    return !!document.querySelector(
      'ytm-miniplayer-ui, ytm-player-mini-container, .ytm-miniplayer-ui, ' +
      '.mini-player, [class*="mini-player"], [class*="miniplayer"]');
  }
  window.__mrplayMiniPlayerInterval = setInterval(function() {
    var s = check();
    if (s !== _lastState) {
      _lastState = s;
      window.flutter_inappwebview.callHandler('miniPlayerStateChanged', s);
    }
  }, 500);
})();
''';

  static const nativeHeaderBack = '''
(function() {
  var btn = document.querySelector('button.header-back-button') ||
            document.querySelector('.ytm-back-button') ||
            document.querySelector('button[aria-label="Back"]') ||
            document.querySelector('.c3-material-button-icon');
  if (btn) btn.click(); else window.history.back();
})();
''';

  static const getVideoTitle = '''
(function() {
  var t = document.querySelector('h1.title yt-formatted-string') ||
          document.querySelector('h1');
  if (t) return t.textContent.trim();
  return document.title.replace(' - YouTube', '').trim();
})();
''';

  static const triggerPip = '''
(function() {
  try {
    var video = document.querySelector('video');
    if (!video) return;
    if (video.paused) video.play().catch(function(){});
    var pipBtn = document.querySelector('.ytp-pip-button') ||
                 document.querySelector('button[aria-label*="Picture"]') ||
                 document.querySelector('[data-title-no-tooltip*="Picture"]');
    if (pipBtn) pipBtn.click();
    if (document.pictureInPictureEnabled && video.requestPictureInPicture) {
      video.requestPictureInPicture().catch(function(){});
    }
  } catch(e) { console.error('[MrPlay] PiP error:', e); }
})();
''';

  static const bgWebViewInject = '''
(function() {
  if (window.__mrplayBgInjected) return;
  window.__mrplayBgInjected = true;
  Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: true });
  Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: true });
  if (!window.__mrplayUserPaused && !window.__mrplayExternallyPaused) {
    var video = document.querySelector('video');
    if (video && video.paused) video.play().catch(function(){});
  }
  window.__mrplayBgInterval = setInterval(function() {
    if (window.__mrplayUserPaused) return;
    if (window.__mrplayExternallyPaused) return;
    var v = document.querySelector('video');
    if (v && v.paused) v.play().catch(function(){});
  }, 2000);
})();
''';
}
