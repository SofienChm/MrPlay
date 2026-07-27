class YouTubeJS {
  static const String adBlockScript = '''
    (function() {
      var adSelectors = [
        '.video-ads',
        '.ytp-ad-module',
        '.ytp-ad-overlay-container',
        '.ytp-ad-text-overlay',
        '#player-ads',
        '.ytp-ad-skip-button-slot',
        'ytd-display-ad-renderer',
        'ytd-promoted-sparkles-web-renderer',
        'ytd-video-masthead-ad-renderer',
        'ytd-banner-promo-renderer',
        '.ytd-ad-slot-renderer',
        'ytd-in-feed-ad-layout-renderer',
        'ytd-ad-slot-renderer',
        '.ytp-ad-progress-list',
        '.ytp-ad-duration-remaining'
      ];

      function hideAds() {
        adSelectors.forEach(function(selector) {
          document.querySelectorAll(selector).forEach(function(el) {
            el.style.display = 'none';
            el.style.visibility = 'hidden';
            el.style.opacity = '0';
          });
        });
      }

      hideAds();
      var observer = new MutationObserver(hideAds);
      observer.observe(document.body, { childList: true, subtree: true });

      setInterval(function() {
        var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button');
        if (skipBtn) skipBtn.click();

        var video = document.querySelector('video');
        var adModule = document.querySelector('.ytp-ad-module');
        if (adModule && video) {
          video.playbackRate = 16;
          setTimeout(function() { video.playbackRate = 1; }, 500);
        }
      }, 1000);

      setInterval(function() {
        var video = document.querySelector('video');
        var titleEl = document.querySelector('h1.title, .slim-video-information-title, .ytp-title');
        var channelEl = document.querySelector('.ytd-channel-name a, .slim-owner-channel-name a');
        var thumbEl = document.querySelector('.ytp-cued-thumbnail-overlay-image');

        var title = titleEl ? titleEl.textContent : '';
        var channel = channelEl ? channelEl.textContent : '';
        var thumb = thumbEl ? thumbEl.style.backgroundImage : '';

        if (window.videoState) {
          window.videoState.postMessage(JSON.stringify({
            isPlaying: video ? !video.paused : false,
            currentTime: video ? video.currentTime : 0,
            duration: video ? video.duration : 0,
            title: title,
            channel: channel,
            thumbnail: thumb
          }));
        }
      }, 500);
    })();
  ''';

  static const String pauseScript = 'document.querySelector("video").pause();';
  static const String playScript = 'document.querySelector("video").play();';
  static const String seekScript = '''
    (function(time) {
      var video = document.querySelector("video");
      if (video) video.currentTime = time;
    })(%s);
  ''';
}
