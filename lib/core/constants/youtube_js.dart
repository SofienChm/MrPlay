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
              position: this.currentTime || 0,
              duration: this.duration || 0,
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

      function shelterPlayingVideo() {
        var v = document.querySelector('video');
        if (!v || v === sheltered) return;
        var isPlaying = !v.paused && !v.ended;
        if (!isPlaying && !inPip(v)) return;
        if (sheltered) {
          try { sheltered.remove(); } catch (e) {}
        }
        ensureShelter().appendChild(v);
        sheltered = v;
      }

      window.__mrplayReleaseSheltered = function(newVideo) {
        if (!sheltered) return;
        if (newVideo && newVideo === sheltered) return;
        try { sheltered.remove(); } catch (e) {}
        sheltered = null;
      };

      document.addEventListener('submit', function(e) {
        var form = e.target;
        if (!form || !form.action) return;
        if (String(form.action).indexOf('/results') === -1) return;
        shelterPlayingVideo();
        if (!sheltered) return;
        e.preventDefault();
        e.stopPropagation();
        var input = form.querySelector('input[name="search_query"]');
        var q = input ? input.value.trim() : '';
        if (!q) return;
        var url = '/results?search_query=' + encodeURIComponent(q);
        try {
          window.history.pushState(window.history.state, '', url);
          window.dispatchEvent(new PopStateEvent('popstate', { state: window.history.state }));
          setTimeout(function() {
            if (document.querySelector('ytd-watch-flexy, ytm-watch, ytd-watch, ytd-watch-flexy')) {
              window.location.href = url;
            }
          }, 1500);
        } catch (err) {
          window.location.href = url;
        }
      }, true);
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

  static const String adBlockScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1) return;
      var adSelectors = [
        '.video-ads', '.ytp-ad-module', '.ytp-ad-overlay-container',
        '.ytp-ad-text-overlay', '#player-ads', '.ytp-ad-skip-button-slot',
        'ytd-display-ad-renderer', 'ytd-promoted-sparkles-web-renderer',
        'ytd-video-masthead-ad-renderer', 'ytd-banner-promo-renderer',
        '.ytd-ad-slot-renderer', 'ytd-in-feed-ad-layout-renderer',
        '.ytp-ad-progress-list', '.ytp-ad-duration-remaining'
      ];

      function hideAds() {
        adSelectors.forEach(function(selector) {
          document.querySelectorAll(selector).forEach(function(el) {
            el.style.display = 'none';
            el.style.visibility = 'hidden';
            el.style.opacity = '0';
          });
        });
      }

      hideAds();
      var adObserver = new MutationObserver(hideAds);
      adObserver.observe(document.body, { childList: true, subtree: true });

      setInterval(function() {
        var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern');
        if (skipBtn) skipBtn.click();
      }, 500);
    })();
  ''';
}
