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
          v.style.objectFit = 'contain';

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
          });
        }

        function reportState() {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler('videoState', {
              playing: !this.paused && !this.ended,
              position: isFinite(this.currentTime) ? this.currentTime : 0,
              // Live streams report duration = Infinity; Dart cannot convert that.
              duration: isFinite(this.duration) ? this.duration : 0,
              ended: !!this.ended
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

      window.__mrplayReleaseSheltered = function(newVideo) {
        if (!sheltered) return;
        if (newVideo && newVideo === sheltered) return;
        // Only release the sheltered video when a real watch-page player starts
        // playing a new video (search hover previews must not close PiP).
        if (newVideo && !newVideo.closest('ytd-watch-flexy, ytd-watch, ytm-watch, #movie_player')) return;
        try { sheltered.remove(); } catch (e) {}
        sheltered = null;
      };

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
        shelterPlayingVideo();
      }, true);

      // SPA navigation: YouTube's router uses history.pushState/replaceState,
      // which fire NEITHER submit NOR popstate. Without these hooks the watch
      // page is torn down, the <video> is destroyed and iOS kills PiP.
      // IMPORTANT: shelter only when navigating AWAY from the watch page to a
      // DIFFERENT page. YouTube also calls replaceState/pushState during normal
      // watch-page playback (tracking params, page-data updates) - sheltering
      // then rips the <video> out of the player and leaves a black box.
      function shouldShelterForUrl(url) {
        if (!url) return false;
        var s = String(url);
        // Navigating to (or staying on) a watch page never needs sheltering.
        if (s.indexOf('/watch') !== -1) return false;
        try {
          var target = new URL(s, location.href);
          // Same path+search = in-place state update, not a real navigation.
          if (target.pathname === location.pathname && target.search === location.search) return false;
        } catch (e) {}
        return true;
      }

      var origPushState = history.pushState;
      history.pushState = function(state, title, url) {
        if (shouldShelterForUrl(url)) shelterPlayingVideo();
        return origPushState.apply(this, arguments);
      };
      var origReplaceState = history.replaceState;
      history.replaceState = function(state, title, url) {
        if (shouldShelterForUrl(url)) shelterPlayingVideo();
        return origReplaceState.apply(this, arguments);
      };

      // YouTube also emits custom navigation lifecycle events. They carry the
      // destination in event.detail - shelter only when a real non-watch URL
      // can be read from it, otherwise the history wrappers above are enough.
      function navEventUrl(e) {
        try {
          var d = e && e.detail;
          if (!d) return null;
          if (d.url) return d.url;
          if (d.endpoint && d.endpoint.url) return d.endpoint.url;
          if (d.response && d.response.url) return d.response.url;
        } catch (err) {}
        return null;
      }

      ['yt-navigate-start', 'ytm-navigate-start'].forEach(function(evt) {
        window.addEventListener(evt, function(e) {
          if (shouldShelterForUrl(navEventUrl(e))) shelterPlayingVideo();
        }, true);
      });
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
}
