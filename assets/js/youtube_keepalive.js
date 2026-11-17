// YouTube background keep-alive: the page always believes it is visible,
// every <video> plays inline with PiP allowed, and playback state is reported
// to the app (events + a 1s heartbeat that survives UI-thread throttling).
(function () {
  if (location.hostname.indexOf('youtube.com') === -1) return;
  if (window.__mrKeepAlive) return;
  window.__mrKeepAlive = true;
  try {
    Object.defineProperty(document, 'hidden', { get: function () { return false; }, configurable: false });
    Object.defineProperty(document, 'webkitHidden', { get: function () { return false; }, configurable: false });
    Object.defineProperty(document, 'visibilityState', { get: function () { return 'visible'; }, configurable: false });
    Object.defineProperty(document, 'webkitVisibilityState', { get: function () { return 'visible'; }, configurable: false });
    document.hasFocus = function () { return true; };

    var style = document.createElement('style');
    style.textContent = 'video { visibility: visible !important; opacity: 1 !important; }';
    (document.head || document.documentElement).appendChild(style);

    var origAdd = EventTarget.prototype.addEventListener;
    var BLOCKED_EVENTS = ['visibilitychange', 'webkitvisibilitychange', 'pagehide', 'beforeunload', 'blur'];
    EventTarget.prototype.addEventListener = function (type, fn, opts) {
      if (BLOCKED_EVENTS.indexOf(type) >= 0) return;
      return origAdd.call(this, type, fn, opts);
    };

    var inlineSet = new WeakSet();
    function makeInline(v) {
      if (inlineSet.has(v)) return;
      v.playsInline = true;
      v.setAttribute('playsinline', 'true');
      v.setAttribute('webkit-playsinline', 'true');
      inlineSet.add(v);
    }
    // YouTube Music sets disablePictureInPicture, which silently refuses the
    // phantom-PiP handoff on background.
    function unblockPiP(v) {
      try {
        v.disablePictureInPicture = false;
        v.removeAttribute('disablepictureinpicture');
      } catch (e) {}
    }

    var origLoad = HTMLMediaElement.prototype.load;
    HTMLMediaElement.prototype.load = function () {
      makeInline(this);
      unblockPiP(this);
      return origLoad.call(this);
    };
    var srcDesc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    if (srcDesc && srcDesc.set) {
      var origSrcSet = srcDesc.set;
      Object.defineProperty(HTMLMediaElement.prototype, 'src', {
        get: srcDesc.get,
        set: function (value) {
          makeInline(this);
          unblockPiP(this);
          origSrcSet.call(this, value);
        },
        configurable: true,
        enumerable: true
      });
    }

    function showVideo(v) {
      v.style.setProperty('visibility', 'visible', 'important');
      v.style.setProperty('opacity', '1', 'important');
      v.style.removeProperty('display');
      v.style.removeProperty('clip');
      v.style.removeProperty('clip-path');
      v.style.removeProperty('width');
      v.style.removeProperty('height');
      v.style.setProperty('object-fit', 'contain', 'important');
      var player = v.closest('#movie_player');
      if (!player) return;
      var poster = player.querySelector('.ytp-cued-thumbnail-overlay, .ytp-poster, .ytp-cued-thumbnail-overlay-image, [class*="thumbnail"][class*="overlay"]');
      if (poster) poster.style.display = 'none';
      var pipOverlay = player.querySelector('.ytp-pip-container');
      if (pipOverlay) pipOverlay.style.display = 'none';
    }

    function report(v) { if (window.__mr) window.__mr.report(v); }

    var lastReport = 0;
    var prepared = new WeakSet();
    function prepareVideo(v) {
      makeInline(v);
      unblockPiP(v);
      if (prepared.has(v)) return;
      prepared.add(v);
      ['play', 'pause', 'ended', 'durationchange'].forEach(function (type) {
        v.addEventListener(type, function () { report(v); });
      });
      v.addEventListener('timeupdate', function () {
        var now = Date.now();
        if (now - lastReport < 250) return;
        lastReport = now;
        report(v);
      });
      v.addEventListener('playing', function () { showVideo(v); });
    }

    document.querySelectorAll('video').forEach(prepareVideo);
    new MutationObserver(function (mutations) {
      mutations.forEach(function (m) {
        m.addedNodes.forEach(function (n) { if (n.nodeName === 'VIDEO') prepareVideo(n); });
      });
    }).observe(document.documentElement, { childList: true, subtree: true });

    // Heartbeat: reports even while timeupdate is throttled; only the
    // actively-playing element, so ad/stray videos can't overwrite state.
    setInterval(function () {
      document.querySelectorAll('video').forEach(function (v) {
        unblockPiP(v);
        showVideo(v);
        if (!v.paused && !v.ended) report(v);
      });
    }, 1000);
  } catch (e) {}
})();
