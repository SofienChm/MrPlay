// Script-injected popup blocker (Safari/Brave style). Only popups that are a
// direct, recent answer to the user tapping a real link — or that target a
// trusted auth host — reach the native new-window gate.
(function () {
  try {
    if (window.__mrPopupGuard) return;
    window.__mrPopupGuard = true;
    var origOpen = window.open;
    if (typeof origOpen !== 'function') return;

    var TRUSTED_HOSTS = /(^|\.)(youtube\.com|youtu\.be|google\.com|googleapis\.com|accounts\.google\.com)$/i;
    var TAP_WINDOW = 700;
    var FLOOD_GAP = 1200;
    var lastTapAt = 0;
    var lastAnchorUrl = '';
    var lastAllowedAt = 0;

    function trackTap(e) {
      try {
        lastTapAt = Date.now();
        var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
        lastAnchorUrl = a ? a.href : '';
      } catch (err) {}
    }
    ['pointerdown', 'mousedown', 'touchstart', 'touchend', 'click'].forEach(function (type) {
      document.addEventListener(type, trackTap, true);
    });
    document.addEventListener('keydown', function () {
      lastTapAt = Date.now();
      lastAnchorUrl = '';
    }, true);

    window.open = function (url) {
      try {
        if (window.__mrPopupOff === true) return origOpen.apply(this, arguments);
        var now = Date.now();
        if (now - lastTapAt > TAP_WINDOW) return null;
        var raw = url && typeof url.href === 'string' ? url.href : String(url || '');
        var resolved = raw;
        var host = '';
        try { resolved = new URL(raw, location.href).href; } catch (e) {}
        try { host = new URL(resolved).hostname; } catch (e) {}
        var anchorMatch = lastAnchorUrl !== '' && resolved.indexOf(lastAnchorUrl) === 0;
        if (!anchorMatch && !TRUSTED_HOSTS.test(host)) return null;
        if (now - lastAllowedAt < FLOOD_GAP) return null;
        lastAllowedAt = now;
        return origOpen.apply(this, arguments);
      } catch (e) {
        return null;
      }
    };
  } catch (e) {}
})();
