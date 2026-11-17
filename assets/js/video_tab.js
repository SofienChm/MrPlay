// Video-tab only: hides the YouTube masthead, double-tap to seek ±10s on the
// inline player, and swipe-down to collapse the tab (WKWebView eats native
// touches, so the swipe is detected in-page and sent to the app).
(function () {
  if (location.hostname.indexOf('youtube.com') === -1) return;

  // --- Header remover (installed once) ---
  if (!window.__mrHeaderRemover) {
    window.__mrHeaderRemover = true;
    var HEADER = [
      '#masthead', '#masthead-container', 'ytd-masthead', 'ytm-masthead',
      'ytd-topbar-logo-renderer', 'ytm-topbar-logo-renderer', '.mobile-topbar-header',
      '.ytp-chrome-top:not(.ytp-visible)', 'ytm-topbar', '#tabsContainer',
      'ytd-page-manager > ytd-rich-grid-renderer ytd-banner-promo-renderer'
    ].join(',');
    var hideQueued = false;
    var hideHeader = function () {
      document.querySelectorAll(HEADER).forEach(function (el) {
        el.style.setProperty('display', 'none', 'important');
      });
    };
    hideHeader();
    new MutationObserver(function () {
      if (hideQueued) return;
      hideQueued = true;
      requestAnimationFrame(function () { hideQueued = false; hideHeader(); });
    }).observe(document.documentElement, { childList: true, subtree: true });
  }

  // --- Double-tap seek (installed once) ---
  if (!window.__mrDoubleTap) {
    window.__mrDoubleTap = true;
    var SEEK = 10;
    var lastTime = 0, lastX = 0, lastY = 0;

    var findPlayer = function (el) {
      while (el && el !== document.documentElement) {
        if (el.tagName === 'VIDEO') return el.closest('.html5-video-player') || el.parentElement;
        if (el.id === 'movie_player' || (el.classList && el.classList.contains('html5-video-player'))) return el;
        el = el.parentElement;
      }
      return null;
    };
    var isControl = function (el) {
      return !!(el.closest && el.closest(
        'button, a, input, [role="button"], .ytp-chrome-bottom, .ytp-chrome-top, ' +
        '.ytp-progress-bar-container, .ytp-popup, .ytp-ce-element, .ytp-endscreen-content'));
    };
    var isFullscreen = function (v) {
      return !!(document.fullscreenElement || document.webkitFullscreenElement || (v && v.webkitDisplayingFullscreen));
    };
    var flash = function (player, left, text) {
      try {
        var d = document.createElement('div');
        d.textContent = text;
        d.style.cssText = 'position:absolute;top:0;bottom:0;width:38%;' +
          (left ? 'left:0;border-radius:0 50% 50% 0;' : 'right:0;border-radius:50% 0 0 50%;') +
          'display:flex;align-items:center;justify-content:center;' +
          'background:rgba(255,255,255,0.18);color:#fff;font:600 15px -apple-system,sans-serif;' +
          'pointer-events:none;z-index:70;opacity:1;transition:opacity 0.5s ease;';
        player.appendChild(d);
        setTimeout(function () { d.style.opacity = '0'; }, 250);
        setTimeout(function () { if (d.parentNode) d.parentNode.removeChild(d); }, 800);
      } catch (e) {}
    };

    document.addEventListener('touchend', function (e) {
      if (!e.changedTouches || e.changedTouches.length !== 1) return;
      if (e.touches && e.touches.length > 0) { lastTime = 0; return; }
      var target = e.target;
      var player = findPlayer(target);
      if (!player || isControl(target)) { lastTime = 0; return; }
      var v = window.__mr ? window.__mr.activeVideo() : null;
      if (isFullscreen(v)) return;

      var t = e.changedTouches[0];
      var now = Date.now();
      var isDouble = lastTime > 0 && (now - lastTime) < 300 &&
        Math.abs(t.clientX - lastX) < 70 && Math.abs(t.clientY - lastY) < 70;
      if (!isDouble) { lastTime = now; lastX = t.clientX; lastY = t.clientY; return; }
      lastTime = 0;

      if (!v || !isFinite(v.duration)) return;
      var rect = player.getBoundingClientRect();
      if (rect.width <= 0) return;
      var rel = (t.clientX - rect.left) / rect.width;
      if (rel > 0.38 && rel < 0.62) return;
      var left = rel <= 0.38;
      try {
        v.currentTime = Math.max(0, Math.min(v.duration, v.currentTime + (left ? -SEEK : SEEK)));
      } catch (err) { return; }
      flash(player, left, left ? '-' + SEEK + 's' : '+' + SEEK + 's');
      e.preventDefault();
      e.stopPropagation();
    }, { capture: true, passive: false });
  }

  // --- Swipe-down collapse (re-installs cleanly on every run: the app
  // re-injects it when the tab re-expands, since WKWebView can drop handlers) ---
  if (window.__mrSwipeCleanup) { try { window.__mrSwipeCleanup(); } catch (e) {} }
  var startY = null, startX = null, startTarget = null, fired = false;

  function isVideoTarget(el) {
    while (el && el !== document.documentElement) {
      if (el.tagName === 'VIDEO') return true;
      if (el.classList && (el.classList.contains('html5-video-container') ||
          el.classList.contains('html5-video-player') ||
          el.classList.contains('video-stream') || el.id === 'movie_player')) return true;
      el = el.parentElement;
    }
    return false;
  }
  function onTouchStart(e) {
    if (!e.touches || !e.touches[0]) return;
    startY = e.touches[0].clientY;
    startX = e.touches[0].clientX;
    startTarget = e.target;
    fired = false;
  }
  function onTouchMove(e) {
    if (startY === null || fired || !e.touches || !e.touches[0]) return;
    var dy = e.touches[0].clientY - startY;
    var dx = Math.abs(e.touches[0].clientX - startX);
    var scrollTop = window.scrollY || document.documentElement.scrollTop || 0;
    if (dy > 60 && dx < 40 && (isVideoTarget(startTarget) || scrollTop <= 2)) {
      fired = true;
      startY = null;
      startX = null;
      if (window.__mr) window.__mr.bridge('videoTabSwipe', {});
    }
  }
  document.addEventListener('touchstart', onTouchStart, { passive: true, capture: true });
  document.addEventListener('touchmove', onTouchMove, { passive: true, capture: true });
  window.__mrSwipeCleanup = function () {
    document.removeEventListener('touchstart', onTouchStart, true);
    document.removeEventListener('touchmove', onTouchMove, true);
  };
})();
