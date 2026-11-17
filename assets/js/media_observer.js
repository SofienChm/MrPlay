// Generic <video> observer for non-YouTube platforms (Twitch, Rumble,
// Dailymotion...): reports playback state and one `playerInfo` (title and
// thumbnail from page meta) once a video starts.
(function () {
  var host = location.hostname;
  if (host.indexOf('youtube.com') !== -1 || host.indexOf('youtu.be') !== -1) return;
  if (window.__mrObserver) return;
  window.__mrObserver = true;

  var lastReport = 0;
  var reported = {};

  function platformName() {
    var h = location.hostname;
    if (h.indexOf('m.') === 0) h = h.substring(2);
    else if (h.indexOf('www.') === 0) h = h.substring(4);
    var first = h.split('.')[0] || '';
    if (!first) return 'Web';
    return first.charAt(0).toUpperCase() + first.slice(1);
  }

  function meta(selector) {
    var el = document.querySelector(selector);
    return el && el.content ? el.content : '';
  }

  function sendPlayerInfo() {
    var key = location.href;
    if (reported[key]) return;
    reported[key] = true;
    var h1 = document.querySelector('h1');
    var title = meta('meta[property="og:title"]') || meta('meta[name="twitter:title"]') ||
      (h1 && h1.textContent ? h1.textContent.trim() : '') || document.title || '';
    window.__mr.bridge('playerInfo', {
      id: location.href,
      title: title.substring(0, 200),
      thumbnailUrl: meta('meta[property="og:image"]'),
      videoUrl: location.href,
      platform: platformName()
    });
  }

  var prepared = new WeakSet();
  function prepare(v) {
    if (prepared.has(v)) return;
    prepared.add(v);
    v.addEventListener('playing', function () { sendPlayerInfo(); window.__mr.report(v); });
    ['play', 'pause', 'ended'].forEach(function (type) {
      v.addEventListener(type, function () { window.__mr.report(v); });
    });
    v.addEventListener('timeupdate', function () {
      var now = Date.now();
      if (now - lastReport < 250) return;
      lastReport = now;
      window.__mr.report(v);
    });
    if (!v.paused && !v.ended) { sendPlayerInfo(); window.__mr.report(v); }
  }

  if (!window.__mr) return;
  document.querySelectorAll('video').forEach(prepare);
  new MutationObserver(function (mutations) {
    mutations.forEach(function (m) {
      m.addedNodes.forEach(function (n) { if (n.nodeName === 'VIDEO') prepare(n); });
    });
  }).observe(document.documentElement, { childList: true, subtree: true });
})();
