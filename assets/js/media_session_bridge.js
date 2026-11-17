// Lock-screen / Control Center play-pause bridge.
// WebKit owns the lock-screen controls: it delivers play/pause to the page's
// Media Session handlers as a trusted gesture, so a lock-screen play is allowed
// (and audible) even after a long background pause. We keep our handlers
// installed (WebKit drops handlers set before media plays, so they are re-set
// on every `playing`), still run the page's own handler, and tell the app.
(function () {
  if (window.__mrMediaBridge) return;
  window.__mrMediaBridge = true;
  try {
    var ms = navigator.mediaSession;
    if (!ms || typeof ms.setActionHandler !== 'function') return;
    var orig = ms.setActionHandler.bind(ms);
    var pageHandlers = {};

    function activeVideo() {
      return window.__mr ? window.__mr.activeVideo() : document.querySelector('video');
    }

    function handlerFor(action) {
      return function (details) {
        window.__mrUserPaused = (action === 'pause');
        if (window.__mr) window.__mr.bridge('mediaCommand', { action: action });
        var v = activeVideo();
        if (v) {
          try {
            if (action === 'play') {
              if (v.playbackRate === 0) v.playbackRate = 1;
              var p = v.play();
              if (p && p.catch) p.catch(function () {});
            } else {
              v.pause();
            }
          } catch (e) {}
        }
        var h = pageHandlers[action];
        if (h) { try { h(details); } catch (e) {} }
      };
    }

    ms.setActionHandler = function (action, handler) {
      if (action === 'play' || action === 'pause') {
        pageHandlers[action] = handler || null;
        return;
      }
      return orig(action, handler);
    };

    function install() {
      try {
        orig('play', handlerFor('play'));
        orig('pause', handlerFor('pause'));
      } catch (e) {}
    }
    install();
    document.addEventListener('playing', function () {
      window.__mrUserPaused = false;
      install();
    }, true);
  } catch (e) {}
})();
