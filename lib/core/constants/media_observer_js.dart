/// Generic `<video>` observer for non-YouTube platforms.
///
/// YouTube has its own dedicated scripts (`visibilityKeepAliveScript` handles
/// inline/PiP/state reporting for m.youtube.com). Every other platform (Twitch,
/// Rumble, Dailymotion, ...) is covered here so the mini player, playback stats
/// and controls still work: it reports `videoState` (position/duration/playing)
/// and sends a single `playerInfo` (title/thumbnail extracted from page meta)
/// once a video starts playing.
class MediaObserverJS {
  static const String genericObserverScript = '''
    (function() {
      var host = location.hostname;
      if (host.indexOf('youtube.com') !== -1 || host.indexOf('youtu.be') !== -1) return;

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

      function extractInfo() {
        var title = '';
        var ogTitle = document.querySelector('meta[property="og:title"]');
        var twTitle = document.querySelector('meta[name="twitter:title"]');
        var h1 = document.querySelector('h1');
        if (ogTitle && ogTitle.content) title = ogTitle.content;
        else if (twTitle && twTitle.content) title = twTitle.content;
        else if (h1 && h1.textContent && h1.textContent.trim()) title = h1.textContent.trim();
        if (!title) title = document.title || '';
        var thumb = '';
        var ogImg = document.querySelector('meta[property="og:image"]');
        if (ogImg && ogImg.content) thumb = ogImg.content;
        return { title: title, thumbnailUrl: thumb };
      }

      function callHandler(name, payload) {
        try {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler(name, payload);
          }
        } catch (e) {}
      }

      function sendPlayerInfo() {
        var key = location.href;
        if (reported[key]) return;
        reported[key] = true;
        var info = extractInfo();
        callHandler('playerInfo', {
          id: location.href,
          title: (info.title || '').substring(0, 200),
          thumbnailUrl: info.thumbnailUrl || '',
          videoUrl: location.href,
          platform: platformName()
        });
      }

      function report(v) {
        var pipStuck = false;
        var pipActive = false;
        try {
          pipStuck = (typeof v.webkitPresentationMode !== 'undefined') &&
                     v.webkitPresentationMode === 'picture-in-picture';
          pipActive = (typeof document.pictureInPictureElement !== 'undefined' &&
                       !!document.pictureInPictureElement);
        } catch (e) {}
        callHandler('videoState', {
          playing: !v.paused && !v.ended,
          position: isFinite(v.currentTime) ? v.currentTime : 0,
          duration: isFinite(v.duration) ? v.duration : 0,
          ended: !!v.ended,
          pip: pipStuck || pipActive,
          pipActive: pipActive,
          pipStuck: pipStuck && !pipActive
        });
      }

      function prepare(v) {
        v.addEventListener('playing', function() { sendPlayerInfo(); report(v); });
        v.addEventListener('play', function() { report(v); });
        v.addEventListener('pause', function() { report(v); });
        v.addEventListener('ended', function() { report(v); });
        v.addEventListener('timeupdate', function() {
          var now = Date.now();
          if (now - lastReport < 250) return;
          lastReport = now;
          report(v);
        });
        if (!v.paused && !v.ended) {
          sendPlayerInfo();
          report(v);
        }
      }

      document.querySelectorAll('video').forEach(prepare);
      new MutationObserver(function(mutations) {
        mutations.forEach(function(m) {
          m.addedNodes.forEach(function(n) {
            if (n.nodeName === 'VIDEO') prepare(n);
          });
        });
      }).observe(document.documentElement, { childList: true, subtree: true });
    })();
  ''';
}
