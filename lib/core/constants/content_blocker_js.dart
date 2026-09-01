class ContentBlockerJS {
  /// Shared blocklist of ad/tracker domains. Used by the DOM-based
  /// [genericAdBlockerScript] and the network-level [adRequestBlockerScript] so
  /// the pattern stays in one place. Deliberately excludes googlevideo.com:
  /// that host also serves real video content, so blocking it would break
  /// playback.
  static const String _adBlockedHostsPattern =
      r'(doubleclick\.net|googlesyndication\.com|googleadservices\.com|adservice\.google|amazon-adsystem\.com|adnxs\.com|adform\.net|taboola\.com|outbrain\.com|pubmatic\.com|criteo\.com|rubiconproject\.com|adsrvr\.org|tremorhub\.com|springserve\.com)';

  /// Layer 1 — strips ad/mid-roll data out of the player response before the
  /// player ever reads it. Two parts: an accessor on `ytInitialPlayerResponse`
  /// that scrubs the raw assignment, and a `fetch` override that reparses
  /// `/youtubei/v1/player` responses and rebuilds them without ad fields. Both
  /// are wrapped so any failure silently falls back to original behavior. On a
  /// parse failure the untouched original response is returned, never a
  /// broken/undefined one.
  static const String stripAdDataScript = '''
    (function() {
      try {
        var AD_KEYS = ['adPlacements', 'adSlots', 'playerAds', 'adBreakHeartbeatParams'];

        function stripAds(obj) {
          try {
            if (!obj || typeof obj !== 'object') return;
            for (var i = 0; i < AD_KEYS.length; i++) {
              try { delete obj[AD_KEYS[i]]; } catch (e) {}
            }
            for (var k in obj) {
              try {
                if (typeof obj[k] === 'object') stripAds(obj[k]);
              } catch (e) {}
            }
          } catch (e) {}
        }

        try {
          var _stored = window.ytInitialPlayerResponse || null;
          Object.defineProperty(window, 'ytInitialPlayerResponse', {
            configurable: true,
            enumerable: true,
            get: function() { return _stored; },
            set: function(val) {
              try {
                if (val && typeof val === 'object') stripAds(val);
              } catch (e) {}
              _stored = val;
            }
          });
        } catch (e) {}

        var _origFetch = window.fetch;
        if (typeof _origFetch === 'function') {
          window.fetch = function() {
            try {
              var _target = arguments[0];
              var _url = typeof _target === 'string' ? _target : (_target && _target.url) || '';
              if (typeof _url === 'string' && _url.indexOf('/youtubei/v1/player') !== -1) {
                return _origFetch.apply(this, arguments).then(function(resp) {
                  try {
                    if (!resp || !resp.clone) return resp;
                    return resp.clone().text().then(function(body) {
                      try {
                        var data = JSON.parse(body);
                        stripAds(data);
                        return new Response(JSON.stringify(data), {
                          status: resp.status,
                          statusText: resp.statusText,
                          headers: resp.headers
                        });
                      } catch (e) {
                        return resp;
                      }
                    }, function() {
                      return resp;
                    });
                  } catch (e) {
                    return resp;
                  }
                });
              }
              return _origFetch.apply(this, arguments);
            } catch (e) {
              return _origFetch.apply(this, arguments);
            }
          };
        }
      } catch (e) {}
    })();
  ''';

  /// Layer 2 — blocks known ad-network request URLs at the network layer.
  /// Overrides `window.fetch` and `XMLHttpRequest.prototype.open` and matches
  /// against the shared [_adBlockedHostsPattern]. Blocked fetch calls reject
  /// (never throw synchronously); blocked XHRs are dropped before `send` so no
  /// network request is made. Only clearly separate ad domains are matched, so
  /// googlevideo.com (real video CDN) is never touched.
  static const String adRequestBlockerScript = '''
    (function() {
      try {
        var BLOCKED_HOSTS = /$_adBlockedHostsPattern/i;

        var _origFetch = window.fetch;
        if (typeof _origFetch === 'function') {
          window.fetch = function() {
            try {
              var _target = arguments[0];
              var _url = typeof _target === 'string' ? _target : (_target && _target.url) || '';
              if (typeof _url === 'string' && BLOCKED_HOSTS.test(_url)) {
                return Promise.reject(new TypeError('Blocked by MrPlay'));
              }
              return _origFetch.apply(this, arguments);
            } catch (e) {
              return _origFetch.apply(this, arguments);
            }
          };
        }

        var _xhrOpen = XMLHttpRequest.prototype.open;
        var _xhrSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url) {
          try {
            this.__mrAdBlocked = !!(url && BLOCKED_HOSTS.test('' + url));
          } catch (e) {
            this.__mrAdBlocked = false;
          }
          return _xhrOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function() {
          try {
            if (this.__mrAdBlocked) {
              this.responseText = '';
              return;
            }
          } catch (e) {}
          return _xhrSend.apply(this, arguments);
        };
      } catch (e) {}
    })();
  ''';

  static const String genericAdBlockerScript = '''
    (function() {
      var BLOCKED_HOSTS = /$_adBlockedHostsPattern/i;

      var SELECTORS = [
        '[data-ad-slot]',
        '[data-ad-client]',
        '[data-ad-zone]',
        '[data-google-query-id]',
        '[data-ad-unit]',
        '.adsbygoogle',
        '[class*="ad-slot"]',
        '[class*="ad-banner"]',
        '[class*="ad-container"]',
        '[class*="advert"]',
        '[class*="sponsored"]',
        '[class*="sponsor"]',
        '[id*="google_ads"]',
        '[id*="google_ads_iframe"]',
        '[id*="advert"]',
        'iframe[src*="doubleclick.net"]',
        'iframe[src*="googlesyndication.com"]',
        'iframe[src*="googleadservices.com"]',
        'iframe[src*="adservice.google"]',
        'iframe[src*="amazon-adsystem"]',
        'iframe[src*="taboola"]',
        'iframe[src*="outbrain"]',
        'iframe[src*="adnxs"]',
        'ytd-display-ad-renderer',
        'ytd-promoted-sparkles-web-renderer',
        'ytd-video-masthead-ad-renderer',
        'ytd-banner-promo-renderer',
        'ytd-ad-slot-renderer',
        'ytd-in-feed-ad-layout-renderer',
        '.video-ads',
        '.ytp-ad-module',
        '.ytp-ad-overlay-container',
        '.ytp-ad-text-overlay',
        '.ytp-ad-skip-button-slot',
        '#player-ads',
        '.ytp-ad-progress-list',
        '.ytp-ad-duration-remaining',
        '.ytp-ad-simple-ad-badge',
        '.ytp-ad-player-overlay'
      ];

      function hide(el) {
        try {
          el.style.display = 'none';
          el.style.visibility = 'hidden';
          el.style.opacity = '0';
          el.setAttribute('aria-hidden', 'true');
        } catch (e) {}
      }

      function hideAdIframes() {
        try {
          document.querySelectorAll('iframe').forEach(function(f) {
            if (BLOCKED_HOSTS.test(f.src || '')) hide(f);
          });
        } catch (e) {}
      }

      function blockAds() {
        try {
          SELECTORS.forEach(function(sel) {
            document.querySelectorAll(sel).forEach(hide);
          });
          hideAdIframes();
        } catch (e) {}
      }

      blockAds();
      new MutationObserver(function() {
        requestAnimationFrame(blockAds);
      }).observe(document.documentElement, { childList: true, subtree: true });

      setInterval(function() {
        var btn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern');
        if (btn) btn.click();
      }, 500);
    })();
  ''';

  /// Layer 3 — masked instant-skip safety net. Acts only on a *live* re-check
  /// of `ad-showing`, prefers a real skip-button click, and only jumps
  /// `currentTime` when the playing ad is a sane short duration (<= 121s) so a
  /// real video can never be cut off. Ad presence drives the flow via a
  /// MutationObserver on the player's class attribute; the only interval is the
  /// unmute safety net. Everything is inside one outer try/catch: any failure
  /// simply means no ad-blocking that session, never broken playback.
  static const String adFallbackSkipScript = '''
    (function() {
      try {
        var _state = { weMuted: false };

        function _player() {
          return document.querySelector('.html5-video-player');
        }

        function _video() {
          var videos = document.querySelectorAll('video');
          for (var i = 0; i < videos.length; i++) {
            if (!videos[i].paused && !videos[i].ended) return videos[i];
          }
          return videos.length > 0 ? videos[0] : null;
        }

        function _adShowing() {
          var p = _player();
          return !!(p && p.classList.contains('ad-showing'));
        }

        var _overlay = null;
        var _maskStyleAdded = false;

        function _ensureMask() {
          try {
            var p = _player();
            if (!p) return;
            if (_overlay && _overlay.isConnected) return;
            if (!_maskStyleAdded) {
              _maskStyleAdded = true;
              var st = document.createElement('style');
              st.id = '__mr_ad_style';
              st.textContent = '@keyframes __mrSpin { to { transform: rotate(1turn); } }';
              (document.head || document.documentElement).appendChild(st);
            }
            _overlay = document.createElement('div');
            _overlay.id = '__mr_ad_mask';
            _overlay.style.cssText = 'position:absolute;top:0;left:0;right:0;bottom:0;background:#000;z-index:99999;transition:opacity 0.35s ease-out;opacity:1;';
            _overlay.innerHTML = '<div style="position:absolute;top:50%;left:50%;width:44px;height:44px;margin:-22px 0 0 -22px;border:4px solid rgba(255,255,255,0.25);border-top-color:#fff;border-radius:50%;animation:__mrSpin 0.8s linear infinite;"></div>';
            p.appendChild(_overlay);
          } catch (e) {}
        }

        function _clearMask() {
          try {
            if (_overlay && _overlay.isConnected) {
              _overlay.style.opacity = '0';
              var el = _overlay;
              _overlay = null;
              setTimeout(function() {
                try {
                  if (el && el.isConnected && el.parentNode) el.parentNode.removeChild(el);
                } catch (e) {}
              }, 400);
            } else {
              _overlay = null;
            }
          } catch (e) {}
        }

        function _muteForAd(video) {
          try {
            if (!video) return;
            video.muted = true;
            _state.weMuted = true;
            if (!video.__mrAdVolBound) {
              video.__mrAdVolBound = true;
              try {
                video.addEventListener('volumechange', function() {
                  try {
                    if (!video.muted && _adShowing()) {
                      video.muted = true;
                      _state.weMuted = true;
                    }
                  } catch (e) {}
                });
              } catch (e) {}
            }
          } catch (e) {}
        }

        function _handle() {
          try {
            if (!_adShowing()) {
              _clearMask();
              if (_state.weMuted) {
                var v = _video();
                if (v) {
                  _state.weMuted = false;
                  v.muted = false;
                }
              }
              return;
            }

            _ensureMask();
            _muteForAd(_video());

            // Re-verify live ad state synchronously right before any skip/jump.
            var p = _player();
            var v = _video();
            if (!p || !p.classList.contains('ad-showing')) return;

            var btn = p.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button') ||
                      document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
            if (btn) {
              if (p.classList.contains('ad-showing')) {
                try { btn.click(); } catch (e) {}
              }
              return;
            }

            // Unskippable ad: masked jump, gated by a strict duration guard so a
            // real video is never skipped (121s = well under real content while
            // comfortably above any ad).
            if (v && p.classList.contains('ad-showing')) {
              var d = v.duration;
              if (typeof d === 'number' && isFinite(d) && d > 0 && d <= 121) {
                v.currentTime = d;
              }
            }
          } catch (e) {}
        }

        function _attach() {
          try {
            var p = _player();
            if (!p || p.__mrAdWatcher) return;
            p.__mrAdWatcher = true;
            new MutationObserver(function() {
              try { _handle(); } catch (e) {}
            }).observe(p, { attributes: true, attributeFilter: ['class'] });
            _handle();
          } catch (e) {}
        }

        function _bootstrap() {
          try {
            if (_player()) { _attach(); return; }
            var docObs = new MutationObserver(function() {
              try {
                if (_player()) {
                  try { docObs.disconnect(); } catch (e) {}
                  _attach();
                }
              } catch (e) {}
            });
            docObs.observe(document.documentElement, { childList: true, subtree: true });
          } catch (e) {}
        }

        _bootstrap();

        // Unmute safety net only. Catches any case where Layer 3 muted for an
        // ad and then lost track of state: if muted, no ad is live, and the
        // mute was ours, unmute.
        setInterval(function() {
          try {
            var v = _video();
            if (!v) return;
            if (v.muted === true && !_adShowing() && _state.weMuted) {
              _state.weMuted = false;
              v.muted = false;
            }
          } catch (e) {}
        }, 1000);
      } catch (e) {}
    })();
  ''';
}