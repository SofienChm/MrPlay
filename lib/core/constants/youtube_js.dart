class YouTubeJS {
  static const String visibilityKeepAliveScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1) return;
      // YouTube Music plays audio and manages its own player/mini-player UI.
      // The aggressive video-visibility forcing below is only for the regular
      // YouTube video player; on Music it leaves a stuck overlay over the UI.
      var isMusic = location.hostname.indexOf('music.youtube.com') !== -1;

      // After a next/prev navigation the next video autoplays muted (no user
      // gesture). The next/prev handler flags this via sessionStorage; while
      // the window is open, any video that starts playing muted is unmuted
      // (see prepareVideo below).
      var shouldUnmute = false;
      try {
        if (sessionStorage.getItem('__mrplay_unmute') === '1') {
          shouldUnmute = true;
          sessionStorage.removeItem('__mrplay_unmute');
          setTimeout(function() { shouldUnmute = false; }, 10000);
        }
      } catch (e) {}

      try {
        Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: false });
        Object.defineProperty(document, 'webkitHidden', { get: function() { return false; }, configurable: false });
        Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: false });
        Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; }, configurable: false });

        document.hasFocus = function() { return true; };

        if (!isMusic) {
          var style = document.createElement('style');
          style.textContent = 'video { visibility: visible !important; opacity: 1 !important; }';
          document.head.appendChild(style);
        }

        var origAdd = EventTarget.prototype.addEventListener;
        EventTarget.prototype.addEventListener = function(type, fn, opts) {
          if (['visibilitychange', 'webkitvisibilitychange', 'pagehide', 'beforeunload', 'blur'].indexOf(type) >= 0) {
            return;
          }
          return origAdd.call(this, type, fn, opts);
        };

        var _playsInlineSet = new WeakSet();
        var _origLoad = HTMLMediaElement.prototype.load;
        HTMLMediaElement.prototype.load = function() {
          if (!_playsInlineSet.has(this)) {
            this.playsInline = true;
            this.setAttribute('playsinline', 'true');
            this.setAttribute('webkit-playsinline', 'true');
            _playsInlineSet.add(this);
          }
          return _origLoad.call(this);
        };
        (function() {
          var desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
          if (desc && desc.set) {
            var _origSrcSet = desc.set;
            Object.defineProperty(HTMLMediaElement.prototype, 'src', {
              get: desc.get,
              set: function(v) {
                if (!_playsInlineSet.has(this)) {
                  this.playsInline = true;
                  this.setAttribute('playsinline', 'true');
                  this.setAttribute('webkit-playsinline', 'true');
                  _playsInlineSet.add(this);
                }
                _origSrcSet.call(this, v);
              },
              configurable: true, enumerable: true
            });
          }
        })();

        var lastReport = 0;

        function unmute(el) {
          try {
            el.muted = false;
            if (el.volume === 0) el.volume = 1;
            var btn = document.querySelector('.ytp-mute-button');
            if (btn) { try { btn.click(); } catch (e) {} }
          } catch (e) {}
        }

        function prepareVideo(v) {
          if (!_playsInlineSet.has(v)) {
            v.playsInline = true;
            v.setAttribute('playsinline', 'true');
            v.setAttribute('webkit-playsinline', 'true');
            _playsInlineSet.add(v);
          }

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
            var el = this;
            if (shouldUnmute && el.muted) unmute(el);
            if (!isMusic) {
              el.style.setProperty('visibility', 'visible', 'important');
              el.style.setProperty('opacity', '1', 'important');
              el.style.removeProperty('display');
              el.style.removeProperty('clip');
              el.style.removeProperty('clip-path');
              el.style.removeProperty('width');
              el.style.removeProperty('height');
              el.style.setProperty('object-fit', 'contain', 'important');
              var player = el.closest('#movie_player');
              if (player) {
                var poster = player.querySelector('.ytp-cued-thumbnail-overlay, .ytp-poster, .ytp-cued-thumbnail-overlay-image, [class*="thumbnail"][class*="overlay"]');
                if (poster) poster.style.display = 'none';
                var pipOverlay = player.querySelector('.ytp-pip-container');
                if (pipOverlay) pipOverlay.style.display = 'none';
              }
              try {
                if (el.webkitSetPresentationMode &&
                    el.webkitPresentationMode === 'picture-in-picture' &&
                    !document.pictureInPictureElement) {
                  el.webkitSetPresentationMode('inline');
                  // If the API call didn't work and the video is still stuck,
                  // force a DOM reinsertion which resets the iOS presentation
                  // pipeline — this is the only reliable escape from stuck mode.
                  if (el.webkitPresentationMode === 'picture-in-picture') {
                    var parent = el.parentNode;
                    if (parent) {
                      var wasPlaying = !el.paused;
                      var next = el.nextSibling;
                      var ct = el.currentTime;
                      parent.removeChild(el);
                      parent.insertBefore(el, next);
                      el.currentTime = ct;
                      if (wasPlaying) el.play().catch(function(){});
                    }
                  }
                }
              } catch (e) {}
            }
          });

          v.addEventListener('volumechange', function() {
            if (shouldUnmute && this.muted && !this.paused && !this.ended) {
              unmute(this);
            }
          });
        }

        function reportState() {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            var pipStuck = false;
            var pipActive = false;
            try {
              var pm = typeof this.webkitPresentationMode !== 'undefined';
              pipStuck = pm && this.webkitPresentationMode === 'picture-in-picture';
              pipActive = (typeof document.pictureInPictureElement !== 'undefined' && !!document.pictureInPictureElement);
            } catch (e) {}
            window.flutter_inappwebview.callHandler('videoState', {
              playing: !this.paused && !this.ended,
              position: isFinite(this.currentTime) ? this.currentTime : 0,
              duration: isFinite(this.duration) ? this.duration : 0,
              ended: !!this.ended,
              pip: pipStuck || pipActive,
              pipActive: pipActive,
              pipStuck: pipStuck && !pipActive
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

        var _stuckCount = 0;
        setInterval(function() {
          if (isMusic) return;
          document.querySelectorAll('video').forEach(function(v) {
            v.style.setProperty('visibility', 'visible', 'important');
            v.style.setProperty('opacity', '1', 'important');
            v.style.removeProperty('display');
            v.style.removeProperty('clip');
            v.style.removeProperty('clip-path');
            v.style.removeProperty('width');
            v.style.removeProperty('height');
            v.style.setProperty('object-fit', 'contain', 'important');
            var player = v.closest('#movie_player');
            if (player) {
              var poster = player.querySelector('.ytp-cued-thumbnail-overlay, .ytp-poster, .ytp-cued-thumbnail-overlay-image, [class*="thumbnail"][class*="overlay"]');
              if (poster) poster.style.display = 'none';
              var pipOverlay = player.querySelector('.ytp-pip-container');
              if (pipOverlay) pipOverlay.style.display = 'none';
            }
            // Periodic state report: broadcasts position/duration/playing every
            // tick even when `timeupdate`/`play`/`pause` events are throttled
            // (this happens while the full-player overlay covers the webview,
            // freezing the player's UI event loop). Without it Dart's
            // position/duration stop updating for the expanded full player.
            // Only report the actively-playing <video> so ad/stray elements
            // can't overwrite the main video's state.
            if (!v.paused && !v.ended) {
              reportState.call(v);
            }
            try {
              if (v.webkitSetPresentationMode &&
                  v.webkitPresentationMode === 'picture-in-picture' &&
                  !document.pictureInPictureElement) {
                v.webkitSetPresentationMode('inline');
                _stuckCount++;
                // If the API call fails 3 times in a row, force a DOM
                // reinsertion which resets the iOS presentation pipeline.
                if (_stuckCount >= 3) {
                  var parent = v.parentNode;
                  if (parent) {
                    var wasPlaying = !v.paused;
                    var next = v.nextSibling;
                    var ct = v.currentTime;
                    parent.removeChild(v);
                    parent.insertBefore(v, next);
                    v.currentTime = ct;
                    if (wasPlaying) v.play().catch(function(){});
                  }
                  _stuckCount = 0;
                }
              } else {
                _stuckCount = 0;
              }
            } catch (e) {}
          });
        }, 1000);
      } catch (e) {}
    })();
  ''';

  static const String appBannerRemoverScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1) return;

      // CSS shield: hides app-promo elements (case-insensitive attr match) even
      // for localized text and elements added after page load. Kept alongside
      // the DOM removal below for shadow-DOM / dynamic elements.
      var style = document.createElement('style');
      style.textContent = [
        '.ytp-open-app-button',
        'ytd-open-in-app-banner',
        'ytm-open-in-app-banner',
        'ytd-mobile-app-banner-renderer',
        'ytm-mobile-app-banner',
        'ytd-guide-entry-point',
        'ytd-download-promo-renderer',
        '#open-in-app',
        '.open-in-app',
        '[data-open-in-app]',
        '[aria-label*="open" i][aria-label*="app" i]',
        '[aria-label*="open" i][aria-label*="youtube" i]',
        '[aria-label*="get" i][aria-label*="app" i]',
        '[aria-label*="get" i][aria-label*="youtube" i]'
      ].join(',') + ' { display: none !important; visibility: hidden !important; height: 0 !important; }';
      (document.head || document.documentElement).appendChild(style);

      var linkSchemes = /^(youtube|vnd\\.youtube|yt|intent|market):/i;

      function isAppPrompt(el) {
        var t = (el.textContent || '').toLowerCase();
        if (!t) {
          var l = (el.getAttribute('aria-label') || '').toLowerCase();
          t = l;
        }
        if (!t) return false;
        return /open[^a-z0-9]{0,20}(the )?(youtube )?app/.test(t) ||
               /(get|download|install)[^a-z0-9]{0,20}(the )?(youtube )?app/.test(t) ||
               t.indexOf('get youtube') > -1;
      }

      function removeAppUI() {
        document.querySelectorAll('a[href], button[data-url], [href]').forEach(function(el) {
          var href = el.getAttribute('href') || el.getAttribute('data-url') || '';
          if (linkSchemes.test(href)) el.remove();
        });
        document.querySelectorAll('button, a, ytd-button-renderer, ytm-button-renderer, ytm-pivot-bar-item-renderer, ytd-compact-link-renderer, yt-chip-cloud-chip-renderer').forEach(function(el) {
          if (isAppPrompt(el)) el.remove();
        });
      }

      removeAppUI();

      // Debounce: removeAppUI() scans every element with an href/aria-label and
      // reads textContent (forces layout). Running it synchronously on every DOM
      // mutation freezes YouTube Music, whose SPA re-renders constantly.
      var removeScheduled = false;
      function requestRemove() {
        if (removeScheduled) return;
        removeScheduled = true;
        requestAnimationFrame(function() {
          removeScheduled = false;
          removeAppUI();
        });
      }

      new MutationObserver(requestRemove)
        .observe(document.documentElement, { childList: true, subtree: true });
    })();
  ''';

  static const String playerControlsScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1) return;

      var BAR_ID = '__mrplay_player_controls';

      var ICONS = {
        cc: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><path d="M2 7a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2z"/><path d="M10 9.5a2 2 0 0 0-2.5 2.5A2 2 0 0 0 10 14.5"/><path d="M16 9.5a2 2 0 0 0-2.5 2.5 2 2 0 0 0 2.5 2.5"/></svg>',
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
        var pos = getComputedStyle(player).position;
        if (pos !== 'absolute' && pos !== 'relative' && pos !== 'fixed') {
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
          { action: 'fullscreen', title: 'Fullscreen', icon: ICONS.fs }
        ];
        for (var i = 0; i < items.length; i++) {
          bar.appendChild(makeButton(items[i].action, items[i].title, items[i].icon));
        }
        player.appendChild(bar);
      }

      var controlsScheduled = false;
      function requestEnsureBar() {
        if (controlsScheduled) return;
        controlsScheduled = true;
        requestAnimationFrame(function() {
          controlsScheduled = false;
          ensureBar();
        });
      }

      new MutationObserver(requestEnsureBar)
        .observe(document.documentElement, { childList: true, subtree: true });

      ensureBar();
    })();
  ''';
}