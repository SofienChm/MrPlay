class ContentBlockerJS {
  /// Strips video-ad placements from YouTube's InnerTube API responses before
  /// the page consumes them. This is what actually removes pre-roll / mid-roll
  /// / overlay video ads: the player never receives an ad slot, so it simply
  /// never shows one. Runs entirely inside the page (no backend, no extra
  /// network), only touching `youtubei/v1/player`, `youtubei/v1/next` and
  /// `get_ad_break`.
  ///
  /// Three layers so it survives every transport YouTube uses:
  ///  * embedded response — traps the `ytInitialPlayerResponse` assignment
  ///    (and the legacy `ytplayer.config.args.raw_player_response` path) made
  ///    inline during page parse on full loads, scrubbing the initial ad slot
  ///    before the player reads it (the same coverage the iOS build has);
  ///  * fetch — clone the response, parse, delete ad keys, hand back a clean
  ///    Response (content-encoding/length dropped since the body is rebuilt);
  ///  * XMLHttpRequest — shadow `responseText` with the cleaned JSON.
  static const String playerAdsStripperScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1 &&
          location.hostname.indexOf('youtu.be') === -1) return;

      // player / next deliver the initial ad slots; get_ad_break delivers
      // mid-roll breaks. Stripping all three keeps the player from ever
      // receiving an ad slot, so no pre-roll / mid-roll ever plays.
      var PLAYER_RE = /\\/youtubei\\/v1\\/(player|next|get_ad_break)/;

      var AD_KEYS = [
        'adPlacements', 'playerAds', 'adSlots', 'adBreakParams',
        'adBreakHeartbeatParams', 'adParams', 'adLoggingDomain',
        'adModule', 'adJoiningInfo', 'adPlayheadUpdateParams',
        'adCuePoints', 'adBreakHeartbeat', 'adSuspendTrigger',
        'adSkippable', 'adImportantSkip', 'adOverlay', 'adVideoId',
        'adBudgetState', 'adReactiveSlots', 'adInlineContinuation',
        'adMessages', 'adExpiryTimeout', 'adBreakInfo', 'adBreakRenderer',
        'adIntroRenderer', 'adNotice', 'adSkipDenied', 'adPlayerLogging',
        'adDescriptor', 'adDurationSec', 'adId', 'adFlags', 'adType',
        'adUnit', 'adStreamUrl', 'adRenderer', 'adOptions', 'adTags',
        'adTrackingParams', 'adReasons'
      ];

      function stripAds(node) {
        if (!node) return false;
        var changed = false;
        if (Array.isArray(node)) {
          for (var i = 0; i < node.length; i++) {
            if (stripAds(node[i])) changed = true;
          }
          return changed;
        }
        if (typeof node === 'object') {
          for (var k in node) {
            if (!Object.prototype.hasOwnProperty.call(node, k)) continue;
            if (AD_KEYS.indexOf(k) !== -1) {
              delete node[k];
              changed = true;
              continue;
            }
            if (stripAds(node[k])) changed = true;
          }
        }
        return changed;
      }

      // On full page loads the player response (with its initial ad slot) is
      // assigned to `ytInitialPlayerResponse` inline during page parse — it
      // never goes through fetch/XHR, so the overrides below never see it.
      // Trap the setter (plus the legacy `ytplayer` embedded-response path) so
      // the slot is scrubbed before the player boots. Matches the iOS build.
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

      try {
        var _ytpStored = window.ytplayer;
        Object.defineProperty(window, 'ytplayer', {
          configurable: true,
          enumerable: true,
          get: function() { return _ytpStored; },
          set: function(v) {
            try {
              if (v && v.config && v.config.args &&
                  typeof v.config.args.raw_player_response === 'string' &&
                  v.config.args.raw_player_response.indexOf('{') === 0) {
                var parsed = JSON.parse(v.config.args.raw_player_response);
                stripAds(parsed);
                v.config.args.raw_player_response = JSON.stringify(parsed);
              }
            } catch (e) {}
            _ytpStored = v;
          }
        });
      } catch (e) {}

      function cleanText(raw, xhr) {
        if (raw && xhr && PLAYER_RE.test(xhr.__mrpUrl)) {
          try {
            var json = JSON.parse(raw);
            if (stripAds(json)) return JSON.stringify(json);
          } catch (e) {}
        }
        return raw;
      }

      if (window.fetch) {
        var origFetch = window.fetch;
        window.fetch = function(input, init) {
          var url = (typeof input === 'string')
              ? input
              : (input && (input.url || input.href) || '');
          var result = origFetch.apply(this, arguments);
          if (!PLAYER_RE.test(url)) return result;
          return result.then(function(res) {
            if (!res || !res.ok) return res;
            return res.clone().text().then(function(text) {
              try {
                var json = JSON.parse(text);
                if (stripAds(json)) {
                  var headers = new Headers(res.headers);
                  headers.delete('content-encoding');
                  headers.delete('content-length');
                  return new Response(JSON.stringify(json), {
                    status: res.status,
                    statusText: res.statusText,
                    headers: headers
                  });
                }
              } catch (e) {}
              return res;
            });
          });
        };
      }

      if (XMLHttpRequest && XMLHttpRequest.prototype) {
        var proto = XMLHttpRequest.prototype;
        var origOpen = proto.open;
        proto.open = function(method, url, async, user, pass) {
          this.__mrpUrl = (url != null) ? String(url) : '';
          return origOpen.apply(this, arguments);
        };

        var origTextDesc = Object.getOwnPropertyDescriptor(proto, 'responseText');
        if (origTextDesc && origTextDesc.get) {
          Object.defineProperty(proto, 'responseText', {
            configurable: true,
            get: function() {
              var raw;
              try { raw = origTextDesc.get.call(this); } catch (e) { return null; }
              return cleanText(raw, this);
            }
          });
        }

        // responseType === 'json' bypasses responseText: YouTube reads .response
        // (an already-parsed object) instead, so those ad payloads would leak
        // through untouched. Patch it too so they are stripped in place before
        // the player consumes them.
        var origRespDesc = Object.getOwnPropertyDescriptor(proto, 'response');
        if (origRespDesc && origRespDesc.get) {
          Object.defineProperty(proto, 'response', {
            configurable: true,
            get: function() {
              var raw;
              try { raw = origRespDesc.get.call(this); } catch (e) { return null; }
              if (raw && this.__mrpUrl && PLAYER_RE.test(this.__mrpUrl)) {
                if (typeof raw === 'string') {
                  return cleanText(raw, this);
                }
                if (this.responseType === 'json' && typeof raw === 'object') {
                  stripAds(raw);
                }
              }
              return raw;
            }
          });
        }
      }

      // Expose the scrubber for the runtime toggle path so an already-loaded
      // page can be cleaned immediately (see _applyAdBlockRuntime in
      // persistent_webview.dart).
      try { window.__mrStripAds = stripAds; } catch (e) {}
    })();
  ''';

  /// Scrub-only snippet for the runtime toggle path. Runs after
  /// [playerAdsStripperScript] has been injected into an already-loaded page
  /// (where the fetch/XHR overrides can no longer catch past responses) and
  /// cleans the player response that YouTube already assigned to
  /// `ytInitialPlayerResponse` / `ytplayer`. Uses the scrubber exposed by
  /// [playerAdsStripperScript]; a no-op if that script hasn't run yet.
  static const String scrubExistingPlayerResponseScript = '''
    (function() {
      try {
        if (!window.__mrStripAds) return;
        if (window.ytInitialPlayerResponse &&
            typeof window.ytInitialPlayerResponse === 'object') {
          window.__mrStripAds(window.ytInitialPlayerResponse);
        }
        if (window.ytplayer && window.ytplayer.config &&
            window.ytplayer.config.args &&
            typeof window.ytplayer.config.args.raw_player_response === 'string' &&
            window.ytplayer.config.args.raw_player_response.indexOf('{') === 0) {
          try {
            var parsed = JSON.parse(window.ytplayer.config.args.raw_player_response);
            window.__mrStripAds(parsed);
            window.ytplayer.config.args.raw_player_response = JSON.stringify(parsed);
          } catch (e) {}
        }
      } catch (e) {}
    })();
  ''';

  /// Layer 2 — blocks known ad-network request URLs at the network layer.
  /// Overrides `window.fetch` and `XMLHttpRequest.prototype.open` and matches
  /// against the shared host blocklist. Blocked fetch calls reject (never throw
  /// synchronously); blocked XHRs are dropped before `send` so no network
  /// request is made. Only clearly separate ad domains are matched, so
  /// googlevideo.com (real video CDN) is never touched. This complements the
  /// native `WebViewAdBlocker` (shouldInterceptRequest), which cannot see
  /// service-worker, blob, or media-range requests; this JS layer sees every
  /// request the page itself makes.
  static const String adRequestBlockerScript = '''
    (function() {
      try {
        var BLOCKED_HOSTS = /(doubleclick\\.net|googlesyndication\\.com|googleadservices\\.com|adservice\\.google|amazon-adsystem\\.com|adnxs\\.com|adform\\.net|taboola\\.com|outbrain\\.com|pubmatic\\.com|criteo\\.com|rubiconproject\\.com|adsrvr\\.org|tremorhub\\.com|springserve\\.com)/i;

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
      var BLOCKED_HOSTS = /(doubleclick\\.net|googlesyndication\\.com|googleadservices\\.com|adservice\\.google|amazon-adsystem\\.com|adnxs\\.com|adform\\.net|taboola\\.com|outbrain\\.com|pubmatic\\.com|criteo\\.com|rubiconproject\\.com|adsrvr\\.org|tremorhub\\.com|springserve\\.com)/i;

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
        'ytm-promoted-video-renderer',
        'ytm-display-ad-renderer',
        'ytm-companion-ad-renderer',
        'ytm-ad-overlay',
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

      // Debounced re-scan: YouTube Music (and other heavy SPAs) mutate the DOM
      // constantly, and running the full selector sweep on every mutation
      // requestAnimationFrame would otherwise choke the main thread. At most one
      // blockAds() pass runs per animation frame, throttled to every 250ms.
      var blockScheduled = false;
      var lastBlockAt = 0;
      function requestBlock() {
        if (blockScheduled) return;
        blockScheduled = true;
        requestAnimationFrame(function() {
          blockScheduled = false;
          var now = Date.now();
          if (now - lastBlockAt < 250) return;
          lastBlockAt = now;
          blockAds();
        });
      }

      new MutationObserver(requestBlock)
        .observe(document.documentElement, { childList: true, subtree: true });

      // Auto-skip skippable ads as soon as the skip button shows up. Anything
      // that still manages to play is handled by [adFallbackSkipScript]: a
      // masked, muted, duration-guarded instant skip that watches
      // `.html5-video-player` for the `ad-showing` class (the same approach as
      // the iOS build, which is why no ad ever becomes visible there).
      setInterval(function() {
        var btn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-container button, .ytm-skip-ad-button');
        if (btn) { try { btn.click(); } catch (e) {} }
      }, 300);
    })();
  ''';

  /// Layer 3 — masked instant-skip safety net. Acts only on a *live* re-check
  /// of `ad-showing`/`ad-interrupting` on the player container
  /// (`.html5-video-player`, where YouTube actually puts the class), prefers a
  /// real skip-button click, and only jumps `currentTime` when the ad survives a
  /// two-phase confirmation (~250ms + ~350ms apart) AND is a sane short duration
  /// (<= 600s, matching the iOS build), so a real video can never be cut off.
  /// While an ad plays it is
  /// covered by a black mask + spinner and muted, so even an ad served from
  /// googlevideo.com (which no network blocker can block — it also carries the
  /// real video) is invisible and silent. Ad presence drives the flow via a
  /// MutationObserver on the player's class attribute; the only interval is the
  /// unmute safety net. Everything is inside one outer try/catch: any failure
  /// simply means no ad-blocking that session, never broken playback. Ported
  /// from the iOS build and hardened with the two-phase confirmation.
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
          return !!(p && (p.classList.contains('ad-showing') || p.classList.contains('ad-interrupting')));
        }

        var _overlay = null;
        var _maskStyleAdded = false;
        var _adSince = null;
        var _jumpPending = false;

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
            var ads = _adShowing();
            if (!ads) {
              _adSince = null;
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

            if (!_adSince) _adSince = Date.now();
            _ensureMask();
            _muteForAd(_video());

            // Re-verify live ad state synchronously right before any action.
            var p = _player();
            var v = _video();
            if (!p || !_adShowing()) return;

            var btn = p.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button') ||
                      document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
            if (btn) {
              if (_adShowing()) {
                try { btn.click(); } catch (e) {}
              }
              return;
            }

            // Unskippable ad: schedule a two-phase, re-verified masked jump so a
            // stale/flickering `ad-showing` class on real content never survives
            // both confirmations. The first phase requires the ad to have been
            // continuously shown for >= 250ms; the second re-checks live state,
            // skip button, and the duration guard (<= 600s, matching the iOS
            // build and well under any real video) ~350ms later before
            // committing the jump.
            if (v && ads && Date.now() - _adSince >= 250 && !_jumpPending) {
              _jumpPending = true;
              setTimeout(function() {
                try {
                  _jumpPending = false;
                  if (!_adShowing()) return;
                  var btn2 = _player().querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button') ||
                             document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
                  if (btn2) {
                    if (_adShowing()) { try { btn2.click(); } catch (e) {} }
                    return;
                  }
                  var v2 = _video();
                  var d = v2 ? v2.duration : NaN;
                  if (v2 && _adShowing() && typeof d === 'number' && isFinite(d) && d > 0 && d <= 600) {
                    v2.currentTime = d;
                  }
                } catch (e) {}
              }, 350);
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
