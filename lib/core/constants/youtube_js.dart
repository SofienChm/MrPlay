class YouTubeJS {
  static const String visibilityKeepAliveScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1) return;
      try {
        Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: false });
        Object.defineProperty(document, 'webkitHidden', { get: function() { return false; }, configurable: false });
        Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: false });
        Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; }, configurable: false });

        document.hasFocus = function() { return true; };

        var style = document.createElement('style');
        style.textContent = 'video { visibility: visible !important; opacity: 1 !important; }';
        document.head.appendChild(style);

        var origAdd = EventTarget.prototype.addEventListener;
        EventTarget.prototype.addEventListener = function(type, fn, opts) {
          if (['visibilitychange', 'webkitvisibilitychange', 'pagehide', 'beforeunload', 'blur'].indexOf(type) >= 0) {
            return;
          }
          return origAdd.call(this, type, fn, opts);
        };

        var lastReport = 0;
        function prepareVideo(v) {
          v.setAttribute('playsinline', 'true');
          v.setAttribute('webkit-playsinline', 'true');
          v.setAttribute('pip', 'true');

          v.addEventListener('play', reportState);
          v.addEventListener('pause', reportState);
          v.addEventListener('ended', reportState);
          v.addEventListener('durationchange', reportState);
          v.addEventListener('timeupdate', function() {
            var now = Date.now();
            if (now - lastReport < 250) return;
            lastReport = now;
            reportState.call(this);
          });

          v.addEventListener('playing', function() {
            if (window.__mrplayReleaseSheltered) window.__mrplayReleaseSheltered(this);
            var el = this;
            el.style.setProperty('visibility', 'visible', 'important');
            el.style.setProperty('opacity', '1', 'important');
            el.style.removeProperty('display');
            var poster = el.parentElement && el.parentElement.querySelector('.ytp-cued-thumbnail-overlay, .ytp-poster, [class*="thumbnail"][class*="overlay"]');
            if (poster) poster.style.display = 'none';
            var player = el.closest('#movie_player');
            if (player) {
              var pipOverlay = player.querySelector('.ytp-pip-container');
              if (pipOverlay) pipOverlay.style.display = 'none';
            }
          });
        }

        function reportState() {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            var pip = false;
            try {
              pip = (typeof this.webkitPresentationMode !== 'undefined' && this.webkitPresentationMode === 'picture-in-picture') ||
                    (typeof document.pictureInPictureElement !== 'undefined' && !!document.pictureInPictureElement);
            } catch (e) {}
            window.flutter_inappwebview.callHandler('videoState', {
              playing: !this.paused && !this.ended,
              position: isFinite(this.currentTime) ? this.currentTime : 0,
              // Live streams report duration = Infinity; Dart cannot convert that.
              duration: isFinite(this.duration) ? this.duration : 0,
              ended: !!this.ended,
              pip: pip
            });
          }
        }

        document.querySelectorAll('video').forEach(prepareVideo);
        new MutationObserver(function(mutations) {
          mutations.forEach(function(m) {
            m.addedNodes.forEach(function(n) {
              if (n.nodeName === 'VIDEO') prepareVideo(n);
            });
          });
        }).observe(document.documentElement, { childList: true, subtree: true });
      } catch (e) {}
    })();
  ''';

  static const String searchSpaScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1) return;

      var sheltered = null;
      var shelterEl = null;

      function ensureShelter() {
        if (!shelterEl) {
          shelterEl = document.createElement('div');
          shelterEl.id = '__mrplay_shelter';
          shelterEl.style.cssText = 'position:fixed;left:-10000px;top:0;width:1px;height:1px;opacity:0;pointer-events:none;overflow:hidden;';
          document.body.appendChild(shelterEl);
        }
        return shelterEl;
      }

      function inPip(v) {
        if (v && typeof v.webkitPresentationMode !== 'undefined' && v.webkitPresentationMode === 'picture-in-picture') return true;
        if (typeof document.pictureInPictureElement !== 'undefined' && document.pictureInPictureElement) return true;
        return false;
      }

      function isActive(v) {
        return !!v && ((!v.paused && !v.ended) || inPip(v));
      }

      function onWatchPage() {
        return location.pathname.indexOf('/watch') !== -1;
      }

      function shelterPlayingVideo() {
        var v = document.querySelector('video');
        if (!v || v === sheltered) return;
        if (!isActive(v)) return;
        if (sheltered) {
          try { sheltered.remove(); } catch (e) {}
        }
        ensureShelter().appendChild(v);
        sheltered = v;
      }

      // Moves a sheltered <video> back into the visible watch-page player.
      // YouTube mobile REUSES the same <video> element across SPA navigations:
      // when the reused element is the one sitting in the off-screen shelter,
      // the watch page plays it off-screen - black player box, audio only -
      // and the old release guard (newVideo === sheltered -> return) never
      // rescued it.
      function restoreShelteredIntoPlayer() {
        if (!sheltered) return;
        if (shelterEl && sheltered.parentNode === shelterEl) {
          // Still parked in our off-screen shelter.
          if (!onWatchPage()) return;
          var container = document.querySelector('#movie_player .html5-video-container') ||
                          document.querySelector('.html5-video-container') ||
                          document.querySelector('#movie_player') ||
                          document.querySelector('#player');
          if (!container) return;
          // The watch page built a FRESH player with its own <video>: leave the
          // sheltered one alone - __mrplayReleaseSheltered swaps it out as soon
          // as the new video actually plays (keeps PiP audio alive meanwhile).
          if (container.querySelector('video')) return;
          try { container.appendChild(sheltered); } catch (e) { return; }
          sheltered = null;
          return;
        }
        // YouTube re-attached the element into a player on its own: drop our
        // stale state so future navigations can shelter it again.
        if (sheltered.closest('#movie_player, #player, ytm-watch, ytd-watch-flexy, ytd-watch')) {
          sheltered = null;
        }
      }

      window.__mrplayReleaseSheltered = function(newVideo) {
        if (!sheltered) return;
        if (newVideo && newVideo === sheltered) {
          // The sheltered element itself (re)started playback. On a watch page
          // that means YouTube reused it as the page player -> put it back into
          // view. Off the watch page (e.g. search hover previews on /results)
          // keep it sheltered so PiP / background audio survives.
          restoreShelteredIntoPlayer();
          return;
        }
        // Only release the sheltered video when a real watch-page player starts
        // playing a new video (search hover previews must not close PiP).
        if (newVideo && !newVideo.closest('ytd-watch-flexy, ytd-watch, ytm-watch, #movie_player, #player')) return;
        try { sheltered.remove(); } catch (e) {}
        sheltered = null;
      };

      // Safety net for races: the reused element can start playing before the
      // destination player container exists, and YouTube sometimes re-attaches
      // the element silently without any event we hook.
      setInterval(restoreShelteredIntoPlayer, 800);

      // Search: keep the playing/PiP video alive while navigating to results.
      // Do NOT preventDefault - let YouTube's own router drive the navigation.
      document.addEventListener('submit', function(e) {
        var form = e.target;
        if (!form || !form.action) return;
        if (String(form.action).indexOf('/results') === -1) return;
        shelterPlayingVideo();
      }, true);

      // Back/forward navigation: shelter the video before YouTube tears down
      // the watch page, so PiP / background audio survives.
      window.addEventListener('popstate', function() {
        // popstate fires AFTER the URL has already changed. If the destination
        // IS a watch page (back/forward between two videos, or forward back
        // onto the watch page) sheltering would rip the <video> out of the
        // player the user is looking at and leave a BLACK BOX - YouTube swaps
        // /reuses the element itself on watch pages.
        if (onWatchPage()) return;
        shelterPlayingVideo();
      }, true);

      // NOTE: history.pushState/replaceState and yt-navigate-start are NOT
      // hooked. YouTube fires them constantly during normal watch-page playback
      // (tracking params, related-content prefetch, search suggestions) and
      // their destination URLs frequently don't contain '/watch'. Sheltering
      // then rips the <video> out of the player and leaves a BLACK BOX, which
      // was the reported "black video in the YouTube player". Only real user
      // navigations (search form submit, back/forward to a non-watch page)
      // shelter the video, and restoreShelteredIntoPlayer puts the reused
      // element back into view whenever a watch page claims it.
    })();
  ''';

  static const String appBannerRemoverScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1) return;
      var selectors = [
        '.ytp-open-app-button',
        'ytd-open-in-app-banner',
        'ytm-open-in-app-banner',
        'ytd-mobile-app-banner-renderer',
        'ytm-mobile-app-banner',
        'ytd-guide-entry-point',
        '#open-in-app',
        '.open-in-app'
      ];

      function removeAppUI() {
        document.querySelectorAll('a[href^="youtube://"], a[href^="vnd.youtube://"], a[href^="yt://"]').forEach(function(a) {
          a.remove();
        });
        selectors.forEach(function(sel) {
          document.querySelectorAll(sel).forEach(function(el) {
            el.remove();
          });
        });
        document.querySelectorAll('button, a, ytd-button-renderer, ytm-button-renderer').forEach(function(el) {
          var t = (el.textContent || '').toLowerCase();
          if (t.indexOf('open in the youtube app') > -1 || t.indexOf('open in youtube app') > -1 || t.indexOf('watch in the youtube app') > -1 || t.indexOf('get the youtube app') > -1) {
            el.remove();
          }
        });
      }

      removeAppUI();
      new MutationObserver(removeAppUI).observe(document.documentElement, { childList: true, subtree: true });
    })();
  ''';

  /// Adds a small overlay button bar (CC / PiP / Fullscreen) on top of the
  /// actual YouTube player (#movie_player). The buttons stay anchored to the
  /// player across re-renders and fullscreen, and forward taps to Dart via
  /// the 'playerControl' handler so they drive the real <video> element.
  static const String playerControlsScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1) return;

      var BAR_ID = '__mrplay_player_controls';

      var ICONS = {
        cc: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><path d="M2 7a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2z"/><path d="M10 9.5a2 2 0 0 0-2.5 2.5A2 2 0 0 0 10 14.5"/><path d="M16 9.5a2 2 0 0 0-2.5 2.5 2 2 0 0 0 2.5 2.5"/></svg>',
        pip: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2"><rect x="2" y="4" width="20" height="16" rx="2"/><rect x="10" y="11" width="8" height="6"/></svg>',
        fs: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><path d="M8 3H3v5"/><path d="M21 8V3h-5"/><path d="M3 16v5h5"/><path d="M16 21h5v-5"/></svg>'
      };

      function makeButton(action, title, icon) {
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.title = title;
        btn.setAttribute('aria-label', title);
        btn.innerHTML = icon;
        btn.style.cssText = 'width:34px;height:34px;border-radius:50%;border:none;background:rgba(0,0,0,0.55);display:flex;align-items:center;justify-content:center;cursor:pointer;margin:0;padding:0;pointer-events:auto;';
        btn.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler('playerControl', { action: action });
          }
        });
        return btn;
      }

      function ensureBar() {
        var player = document.querySelector('#movie_player');
        if (!player) return;
        if (player.style.position !== 'absolute' && player.style.position !== 'relative') {
          player.style.position = 'relative';
        }
        var bar = document.getElementById(BAR_ID);
        if (bar && player.contains(bar)) return;
        if (bar) bar.remove();
        bar = document.createElement('div');
        bar.id = BAR_ID;
        bar.style.cssText = 'position:absolute;top:10px;left:10px;z-index:100;display:flex;gap:6px;pointer-events:none;';
        var items = [
          { action: 'toggleCaptions', title: 'Captions', icon: ICONS.cc },
          { action: 'pip', title: 'Picture in picture', icon: ICONS.pip },
          { action: 'fullscreen', title: 'Fullscreen', icon: ICONS.fs }
        ];
        for (var i = 0; i < items.length; i++) {
          bar.appendChild(makeButton(items[i].action, items[i].title, items[i].icon));
        }
        player.appendChild(bar);
      }

      new MutationObserver(function() {
        ensureBar();
      }).observe(document.documentElement, { childList: true, subtree: true });

      ensureBar();
    })();
  ''';
}
