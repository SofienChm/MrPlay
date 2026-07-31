class YouTubeJS {
  static const String visibilityKeepAliveScript = '''
    (function() {
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

        function prepareVideo(v) {
          v.setAttribute('playsinline', 'true');
          v.setAttribute('webkit-playsinline', 'true');
          v.setAttribute('pip', 'true');
          v.style.objectFit = 'contain';
          if (!v.getAttribute('data-mrplay-guard')) {
            v.setAttribute('data-mrplay-guard', '1');
            var lastResume = 0;
            v.addEventListener('pause', function() {
              var now = Date.now();
              if (now - lastResume < 3000) return;
              var pipActive = (typeof v.webkitPresentationMode !== 'undefined' && v.webkitPresentationMode === 'picture-in-picture');
              if (!pipActive && typeof document.pictureInPictureElement !== 'undefined') {
                pipActive = document.pictureInPictureElement === v;
              }
              if (pipActive && !v.ended && v.readyState >= 2) {
                lastResume = now;
                v.play().catch(function(){});
              }
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
      function inPip() {
        var v = document.querySelector('video');
        if (v && typeof v.webkitPresentationMode !== 'undefined' && v.webkitPresentationMode === 'picture-in-picture') return true;
        if (typeof document.pictureInPictureElement !== 'undefined' && document.pictureInPictureElement) return true;
        return false;
      }
      document.addEventListener('submit', function(e) {
        var form = e.target;
        if (!form || !form.action) return;
        if (String(form.action).indexOf('/results') === -1) return;
        if (!inPip()) return;
        e.preventDefault();
        e.stopPropagation();
        var input = form.querySelector('input[name="search_query"]');
        var q = input ? input.value.trim() : '';
        if (!q) return;
        var url = '/results?search_query=' + encodeURIComponent(q);
        try {
          window.history.pushState(window.history.state, '', url);
          window.dispatchEvent(new PopStateEvent('popstate', { state: window.history.state }));
        } catch (err) {
          window.location.href = url;
        }
      }, true);
    })();
  ''';

  static const String adBlockScript = '''
    (function() {
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
        
        var video = document.querySelector('video');
        var adModule = document.querySelector('.ytp-ad-module');
        if (adModule && video) {
          video.playbackRate = 16;
          setTimeout(function() { video.playbackRate = 1; }, 500);
        }
      }, 500);
    })();
  ''';
}
