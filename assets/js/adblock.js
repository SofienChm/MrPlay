// MrPlay ad blocker. Four layers, all idempotent and switchable at runtime
// through `window.__mrAdBlockOff = true` (no reload, playback never breaks):
//   1. strip ad data out of YouTube player responses
//   2. block ad-network / ad-ping requests (fetch + XHR)
//   3. hide ad DOM elements and auto-click skip buttons
//   4. masked instant-skip of unskippable ads
// googlevideo.com (the real video CDN) is never matched.
(function () {
  if (window.__mrAdBlockInstalled) {
    window.__mrAdBlockOff = false;
    return;
  }
  window.__mrAdBlockInstalled = true;

  var BLOCKED_HOSTS = /(doubleclick\.net|googlesyndication\.com|googleadservices\.com|adservice\.google|amazon-adsystem\.com|adnxs\.com|adform\.net|taboola\.com|outbrain\.com|pubmatic\.com|criteo\.com|rubiconproject\.com|adsrvr\.org|tremorhub\.com|springserve\.com)/i;
  // Same-origin YouTube ad endpoints no host rule can catch.
  var BLOCKED_PATHS = /(^|youtube\.com)\/(pagead\/|api\/stats\/ads|ptracking)/i;

  function off() { return window.__mrAdBlockOff === true; }

  function urlOf(target) {
    if (typeof target === 'string') return target;
    if (target && typeof target.url === 'string') return target.url;
    if (target && typeof target.href === 'string') return target.href;
    return '';
  }

  // ---------------------------------------------------------------- layer 1
  var AD_KEYS = ['adPlacements', 'adSlots', 'playerAds', 'adBreakHeartbeatParams'];

  function stripAds(obj) {
    try {
      if (off() || !obj || typeof obj !== 'object') return;
      for (var i = 0; i < AD_KEYS.length; i++) {
        try { delete obj[AD_KEYS[i]]; } catch (e) {}
      }
      for (var k in obj) {
        try { if (typeof obj[k] === 'object') stripAds(obj[k]); } catch (e) {}
      }
    } catch (e) {}
  }

  // `get_watch` loads the next video during SPA navigation; `reel_item_watch`
  // is the same for each Short.
  function isPlayerUrl(u) {
    return u.indexOf('/youtubei/v1/player') !== -1 ||
      u.indexOf('/youtubei/v1/get_watch') !== -1 ||
      u.indexOf('/youtubei/v1/reel/reel_item_watch') !== -1;
  }

  function isBlocked(u) {
    if (off()) return false;
    return BLOCKED_HOSTS.test(u) || BLOCKED_PATHS.test(u);
  }

  try {
    var stored = window.ytInitialPlayerResponse || null;
    Object.defineProperty(window, 'ytInitialPlayerResponse', {
      configurable: true,
      enumerable: true,
      get: function () { return stored; },
      set: function (val) {
        try { if (val && typeof val === 'object') stripAds(val); } catch (e) {}
        stored = val;
      }
    });
  } catch (e) {}

  try {
    var ytpStored = window.ytplayer;
    Object.defineProperty(window, 'ytplayer', {
      configurable: true,
      enumerable: true,
      get: function () { return ytpStored; },
      set: function (v) {
        try {
          var args = v && v.config && v.config.args;
          if (args && typeof args.raw_player_response === 'string' &&
              args.raw_player_response.indexOf('{') === 0) {
            var parsed = JSON.parse(args.raw_player_response);
            stripAds(parsed);
            args.raw_player_response = JSON.stringify(parsed);
          }
        } catch (e) {}
        ytpStored = v;
      }
    });
  } catch (e) {}

  // ------------------------------------------------- layers 1 + 2 (network)
  var origFetch = window.fetch;
  if (typeof origFetch === 'function') {
    window.fetch = function () {
      var self = this;
      var args = arguments;
      try {
        var u = urlOf(args[0]);
        if (isBlocked(u)) return Promise.reject(new TypeError('Blocked by MrPlay'));
        if (!off() && isPlayerUrl(u)) {
          return origFetch.apply(self, args).then(function (resp) {
            if (!resp || !resp.clone) return resp;
            return resp.clone().text().then(function (body) {
              try {
                var data = JSON.parse(body);
                stripAds(data);
                return new Response(JSON.stringify(data), {
                  status: resp.status,
                  statusText: resp.statusText,
                  headers: resp.headers
                });
              } catch (e) { return resp; }
            }, function () { return resp; });
          });
        }
      } catch (e) {}
      return origFetch.apply(self, args);
    };
  }

  var xhrOpen = XMLHttpRequest.prototype.open;
  var xhrSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    try {
      var u = urlOf(url) || String(url || '');
      this.__mrUrl = u;
      this.__mrBlocked = isBlocked(u);
    } catch (e) {
      this.__mrUrl = '';
      this.__mrBlocked = false;
    }
    return xhrOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    var xhr = this;
    try {
      if (xhr.__mrBlocked) {
        // Fail like a network error instead of hanging: player code awaiting
        // a never-resolving ad request would block the real video.
        setTimeout(function () {
          try {
            xhr.dispatchEvent(new ProgressEvent('error'));
            xhr.dispatchEvent(new ProgressEvent('loadend'));
          } catch (e) {}
        }, 0);
        return;
      }
      if (!off() && typeof xhr.__mrUrl === 'string' && isPlayerUrl(xhr.__mrUrl)) {
        xhr.addEventListener('load', function () {
          try {
            var raw = xhr.responseText;
            if (!raw) return;
            var data = JSON.parse(raw);
            stripAds(data);
            var fixed = JSON.stringify(data);
            Object.defineProperty(xhr, 'responseText', { configurable: true, writable: false, value: fixed });
            if (!xhr.responseType || xhr.responseType === 'text') {
              Object.defineProperty(xhr, 'response', { configurable: true, writable: false, value: fixed });
            }
          } catch (e) {}
        });
      }
    } catch (e) {}
    return xhrSend.apply(xhr, arguments);
  };

  // ---------------------------------------------------------------- layer 3
  var AD_SELECTOR = [
    '[data-ad-slot]', '[data-ad-client]', '[data-ad-zone]', '[data-google-query-id]', '[data-ad-unit]',
    '.adsbygoogle', '[class*="ad-slot"]', '[class*="ad-banner"]', '[class*="ad-container"]',
    '[class*="advert"]', '[class*="sponsored"]', '[class*="sponsor"]',
    '[id*="google_ads"]', '[id*="google_ads_iframe"]', '[id*="advert"]',
    'iframe[src*="doubleclick.net"]', 'iframe[src*="googlesyndication.com"]',
    'iframe[src*="googleadservices.com"]', 'iframe[src*="adservice.google"]',
    'iframe[src*="amazon-adsystem"]', 'iframe[src*="taboola"]', 'iframe[src*="outbrain"]', 'iframe[src*="adnxs"]',
    'ytd-display-ad-renderer', 'ytd-promoted-sparkles-web-renderer', 'ytd-video-masthead-ad-renderer',
    'ytd-banner-promo-renderer', 'ytd-ad-slot-renderer', 'ytd-in-feed-ad-layout-renderer',
    'ytm-promoted-sparkles-web-renderer', 'ytm-promoted-video-renderer', 'ytm-display-ad-renderer',
    'ytm-ad-slot-renderer', 'ytm-in-feed-ad-layout-renderer', 'ytm-video-masthead-ad-renderer',
    'ytm-companion-slot', 'ytm-companion-ad-renderer', 'ad-slot-renderer',
    '.video-ads', '.ytp-ad-module', '.ytp-ad-overlay-container', '.ytp-ad-text-overlay',
    '.ytp-ad-skip-button-slot', '#player-ads', '.ytp-ad-progress-list',
    '.ytp-ad-duration-remaining', '.ytp-ad-simple-ad-badge', '.ytp-ad-player-overlay'
  ].join(',');
  var SKIP_SELECTOR = '.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern';

  function hide(el) {
    try {
      el.style.display = 'none';
      el.style.visibility = 'hidden';
      el.style.opacity = '0';
      el.setAttribute('aria-hidden', 'true');
    } catch (e) {}
  }

  function hideAds() {
    if (off()) return;
    try {
      document.querySelectorAll(AD_SELECTOR).forEach(hide);
      document.querySelectorAll('iframe').forEach(function (f) {
        if (BLOCKED_HOSTS.test(f.src || '')) hide(f);
      });
    } catch (e) {}
  }

  var hideQueued = false;
  function scheduleHide() {
    if (hideQueued) return;
    hideQueued = true;
    requestAnimationFrame(function () { hideQueued = false; hideAds(); });
  }

  // ---------------------------------------------------------------- layer 4
  // Acts only on a live re-check of `ad-showing` (YouTube never flags real
  // content as an ad) with a 180s cap, so real videos are never skipped.
  var st = { weMuted: false, lastAdAt: 0, mutedEls: [], adStart: 0, maskOff: false, overlay: null, styleAdded: false };

  function player() { return document.querySelector('.html5-video-player'); }
  function video() { return window.__mr ? window.__mr.activeVideo() : document.querySelector('video'); }
  function adShowing() { var p = player(); return !!(p && p.classList.contains('ad-showing')); }

  function restoreMuted() {
    var els = st.mutedEls;
    st.mutedEls = [];
    st.weMuted = false;
    for (var i = 0; i < els.length; i++) {
      try { if (els[i].muted) els[i].muted = false; } catch (e) {}
    }
  }

  function ensureMask() {
    try {
      var p = player();
      if (!p || (st.overlay && st.overlay.isConnected)) return;
      if (!st.styleAdded) {
        st.styleAdded = true;
        var s = document.createElement('style');
        s.textContent = '@keyframes __mrSpin { to { transform: rotate(1turn); } }';
        (document.head || document.documentElement).appendChild(s);
      }
      var o = document.createElement('div');
      o.id = '__mr_ad_mask';
      o.style.cssText = 'position:absolute;top:0;left:0;right:0;bottom:0;background:#000;z-index:99999;transition:opacity 0.35s ease-out;opacity:1;';
      o.innerHTML = '<div style="position:absolute;top:50%;left:50%;width:44px;height:44px;margin:-22px 0 0 -22px;border:4px solid rgba(255,255,255,0.25);border-top-color:#fff;border-radius:50%;animation:__mrSpin 0.8s linear infinite;"></div>';
      p.appendChild(o);
      st.overlay = o;
    } catch (e) {}
  }

  function clearMask() {
    var o = st.overlay;
    st.overlay = null;
    if (!o || !o.isConnected) return;
    o.style.opacity = '0';
    setTimeout(function () { try { if (o.parentNode) o.parentNode.removeChild(o); } catch (e) {} }, 400);
  }

  function muteForAd(v) {
    if (!v) return;
    try {
      v.muted = true;
      st.weMuted = true;
      if (st.mutedEls.indexOf(v) === -1) st.mutedEls.push(v);
      if (!v.__mrAdVolBound) {
        v.__mrAdVolBound = true;
        // Only defend the mute we applied for this ad.
        v.addEventListener('volumechange', function () {
          if (st.weMuted && !v.muted && adShowing()) v.muted = true;
        });
      }
    } catch (e) {}
  }

  function handleAd() {
    try {
      if (off() || !adShowing()) {
        st.adStart = 0;
        st.maskOff = false;
        clearMask();
        if (st.weMuted) restoreMuted();
        return;
      }
      st.lastAdAt = Date.now();
      if (st.adStart === 0) st.adStart = Date.now();
      // Stuck-ad watchdog: an ad whose duration never resolves would leave an
      // endless spinner; drop the mask after 5s but keep trying to skip.
      if (!st.maskOff && Date.now() - st.adStart > 5000) { st.maskOff = true; clearMask(); }
      if (!st.maskOff) ensureMask();
      muteForAd(video());

      var p = player();
      var v = video();
      if (!p || !p.classList.contains('ad-showing')) return;
      var btn = p.querySelector(SKIP_SELECTOR) || document.querySelector(SKIP_SELECTOR);
      if (btn) { try { btn.click(); } catch (e) {} return; }
      if (v && p.classList.contains('ad-showing')) {
        var d = v.duration;
        if (typeof d === 'number' && isFinite(d) && d > 0 && d <= 180) v.currentTime = d;
      }
    } catch (e) {}
  }

  function attachPlayerWatcher() {
    var p = player();
    if (!p || p.__mrAdWatcher) return;
    p.__mrAdWatcher = true;
    new MutationObserver(handleAd).observe(p, { attributes: true, attributeFilter: ['class'] });
    handleAd();
  }

  // ------------------------------------------------------------- bootstrap
  function boot() {
    hideAds();
    attachPlayerWatcher();
    // Stays connected: YouTube replaces the player element on SPA navigation.
    new MutationObserver(function () {
      scheduleHide();
      attachPlayerWatcher();
    }).observe(document.documentElement, { childList: true, subtree: true });

    setInterval(function () {
      if (off()) { if (st.weMuted || st.overlay) handleAd(); return; }
      var btn = document.querySelector(SKIP_SELECTOR);
      if (btn) { try { btn.click(); } catch (e) {} }
    }, 500);

    // Watchdog + unmute safety net.
    setInterval(function () {
      try {
        attachPlayerWatcher();
        if (adShowing()) { handleAd(); return; }
        if (st.mutedEls.length > 0) { restoreMuted(); return; }
        var v = video();
        var recentAd = st.lastAdAt > 0 && Date.now() - st.lastAdAt < 15000;
        if (v && v.muted === true && (st.weMuted || recentAd)) {
          st.weMuted = false;
          v.muted = false;
        }
      } catch (e) {}
    }, 1000);
  }

  if (document.documentElement) boot();
  else document.addEventListener('DOMContentLoaded', boot);
})();
