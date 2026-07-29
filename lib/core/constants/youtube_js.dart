class YouTubeJS {
  static const String adBlockScript = '''
    (function() {
      // Hide ad containers
      const adSelectors = [
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
        adSelectors.forEach(selector => {
          document.querySelectorAll(selector).forEach(el => {
            el.style.display = 'none';
            el.style.visibility = 'hidden';
            el.style.opacity = '0';
          });
        });
      }

      // Run immediately and on DOM changes
      hideAds();
      const observer = new MutationObserver(hideAds);
      observer.observe(document.body, { childList: true, subtree: true });

      // Auto-skip skippable ads
      setInterval(() => {
        const skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button');
        if (skipBtn) skipBtn.click();

        const video = document.querySelector('video');
        const adModule = document.querySelector('.ytp-ad-module');
        if (adModule && video) {
          // Speed through unskippable ads
          video.playbackRate = 16;
          setTimeout(() => { video.playbackRate = 1; }, 500);
        }
      }, 1000);

      // Report player state to Flutter
      setInterval(() => {
        const video = document.querySelector('video');
        const title = document.querySelector('h1.title, .slim-video-information-title, .ytp-title')?.textContent || '';
        const channel = document.querySelector('.ytd-channel-name a, .slim-owner-channel-name a')?.textContent || '';
        const thumb = document.querySelector('.ytp-cued-thumbnail-overlay-image')?.style.backgroundImage || '';

        try {
          window.videoState.postMessage(JSON.stringify({
            isPlaying: video ? !video.paused : false,
            currentTime: video ? video.currentTime : 0,
            duration: video ? video.duration : 0,
            title: title,
            channel: channel,
            thumbnail: thumb
          }));
        } catch(e) {}
      }, 500);
    })();
  ''';

  static const String pauseScript = 'document.querySelector("video").pause();';
  static const String playScript = 'document.querySelector("video").play();';
  static const String seekScript = '''
    (function(time) {
      const video = document.querySelector("video");
      if (video) video.currentTime = time;
    })(%s);
  ''';
}
