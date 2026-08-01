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
      new MutationObserver(function() {
        requestAnimationFrame(blockAds);
      }).observe(document.documentElement, { childList: true, subtree: true });

      setInterval(function() {
        var btn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern');
        if (btn) btn.click();
      }, 500);
    })();
  ''';
}
