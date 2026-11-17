// YouTube page cleanup: removes "Open in app" banners/links and hides the
// "Tap to unmute" popup (the actual unmute is done by the app).
(function () {
  if (location.hostname.indexOf('youtube.com') === -1) return;
  if (window.__mrCleanup) return;
  window.__mrCleanup = true;

  var APP_SELECTORS = [
    '.ytp-open-app-button',
    'ytd-open-in-app-banner',
    'ytm-open-in-app-banner',
    'ytd-mobile-app-banner-renderer',
    'ytm-mobile-app-banner',
    'ytd-guide-entry-point',
    '#open-in-app',
    '.open-in-app'
  ].join(',');
  var APP_LINKS = 'a[href^="youtube://"], a[href^="vnd.youtube://"], a[href^="yt://"]';
  var APP_TEXTS = ['open in the youtube app', 'open in youtube app', 'watch in the youtube app', 'get the youtube app'];

  function removeAppLinks() {
    document.querySelectorAll(APP_LINKS + ',' + APP_SELECTORS).forEach(function (el) { el.remove(); });
  }

  // The text scan reads every button/link, so it runs at most once per 400ms.
  function removeAppByText() {
    document.querySelectorAll('button, a, ytd-button-renderer, ytm-button-renderer').forEach(function (el) {
      var t = (el.textContent || '').toLowerCase();
      for (var i = 0; i < APP_TEXTS.length; i++) {
        if (t.indexOf(APP_TEXTS[i]) > -1) { el.remove(); return; }
      }
    });
  }

  function hideUnmutePopups() {
    try {
      document.querySelectorAll('.ytp-unmute-widget, [class*="unmute"]').forEach(function (el) {
        el.style.setProperty('display', 'none', 'important');
        el.style.setProperty('visibility', 'hidden', 'important');
      });
    } catch (e) {}
  }

  removeAppLinks();
  removeAppByText();
  hideUnmutePopups();

  var frameQueued = false;
  var textTimer = null;
  new MutationObserver(function () {
    if (!frameQueued) {
      frameQueued = true;
      requestAnimationFrame(function () {
        frameQueued = false;
        removeAppLinks();
        hideUnmutePopups();
      });
    }
    if (!textTimer) {
      textTimer = setTimeout(function () {
        textTimer = null;
        removeAppByText();
      }, 400);
    }
  }).observe(document.documentElement, { childList: true, subtree: true });
  setInterval(hideUnmutePopups, 1000);
})();
