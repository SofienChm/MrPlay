class ContentBlockerJS {
  static const String genericAdBlockerScript = '''
    (function() {
      var BLOCKED_HOSTS = /(doubleclick\\.net|googlesyndication\\.com|googleadservices\\.com|adservice\\.google|amazon-adsystem\\.com|adnxs\\.com|adform\\.net|taboola\\.com|outbrain\\.com|pubmatic\\.com|criteo\\.com|rubiconproject\\.com|adsrvr\\.org|tremorhub\\.com|springserve\\.com)/i;

      var SELECTORS = [
        '[data-ad-slot]',
        '[data-ad-client]',
        '[data-ad-zone]',
        '[data-google-query-id]',
        '[data-ad-unit]',
        '.adsbygoogle',
        '[class*="ad-slot"]',
        '[class*="ad-banner"]',
        '[class*="ad-container"]',
        '[class*="advert"]',
        '[class*="sponsored"]',
        '[class*="sponsor"]',
        '[id*="google_ads"]',
        '[id*="google_ads_iframe"]',
        '[id*="advert"]',
        'iframe[src*="doubleclick.net"]',
        'iframe[src*="googlesyndication.com"]',
        'iframe[src*="googleadservices.com"]',
        'iframe[src*="adservice.google"]',
        'iframe[src*="amazon-adsystem"]',
        'iframe[src*="taboola"]',
        'iframe[src*="outbrain"]',
        'iframe[src*="adnxs"]',
        'ytd-display-ad-renderer',
        'ytd-promoted-sparkles-web-renderer',
        'ytd-video-masthead-ad-renderer',
        'ytd-banner-promo-renderer',
        'ytd-ad-slot-renderer',
        'ytd-in-feed-ad-layout-renderer',
        'ytm-promoted-video-renderer',
        'ytm-display-ad-renderer',
        'ytm-companion-ad-renderer',
        'ytm-ad-overlay',
        '.video-ads',
        '.ytp-ad-module',
        '.ytp-ad-overlay-container',
        '.ytp-ad-text-overlay',
        '.ytp-ad-skip-button-slot',
        '#player-ads',
        '.ytp-ad-progress-list',
        '.ytp-ad-duration-remaining',
        '.ytp-ad-simple-ad-badge',
        '.ytp-ad-player-overlay'
      ];

      function hide(el) {
        try {
          el.style.display = 'none';
          el.style.visibility = 'hidden';
          el.style.opacity = '0';
          el.setAttribute('aria-hidden', 'true');
        } catch (e) {}
      }

      function hideAdIframes() {
        try {
          document.querySelectorAll('iframe').forEach(function(f) {
            if (BLOCKED_HOSTS.test(f.src || '')) hide(f);
          });
        } catch (e) {}
      }

      function blockAds() {
        try {
          SELECTORS.forEach(function(sel) {
            document.querySelectorAll(sel).forEach(hide);
          });
          hideAdIframes();
        } catch (e) {}
      }

      blockAds();

      // Debounced re-scan: YouTube Music (and other heavy SPAs) mutate the DOM
      // constantly, and running the full selector sweep on every mutation
      // requestAnimationFrame would otherwise choke the main thread. At most one
      // blockAds() pass runs per animation frame, throttled to every 250ms.
      var blockScheduled = false;
      var lastBlockAt = 0;
      function requestBlock() {
        if (blockScheduled) return;
        blockScheduled = true;
        requestAnimationFrame(function() {
          blockScheduled = false;
          var now = Date.now();
          if (now - lastBlockAt < 250) return;
          lastBlockAt = now;
          blockAds();
        });
      }

      new MutationObserver(requestBlock)
        .observe(document.documentElement, { childList: true, subtree: true });

      // Auto-skip skippable ads and fast-forward unskippable ones (16x playback
      // finishes a 30s ad in ~2s).
      setInterval(function() {
        var btn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-container button, .ytm-skip-ad-button');
        if (btn) { try { btn.click(); } catch (e) {} }

        // YouTube Music uses an <audio> element and its player shares .ytp-*
        // classes with the video player, so the fast-forward hack would falsely
        // speed up music. Skip it there entirely.
        if (location.hostname.indexOf('music.youtube') === 0) return;

        var video = document.querySelector('video');
        if (!video) return;
        // Only speed up when a real video ad is active (YouTube adds the
        // ad-showing / ad-interrupting class to the <video> element).
        var adShowing = video.classList.contains('ad-showing') ||
                        video.classList.contains('ad-interrupting') ||
                        !!document.querySelector('.ytp-ad-player-overlay-layout');
        if (adShowing) {
          if (video.playbackRate !== 16) video.playbackRate = 16;
        } else if (video.playbackRate === 16) {
          video.playbackRate = 1;
        }
      }, 300);
    })();
  ''';
}
