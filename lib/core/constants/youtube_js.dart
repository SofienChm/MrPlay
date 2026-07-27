class YouTubeJS {
  static const String adBlockScript = '''
    (function() {
      var adSelectors = [
        '.video-ads', '.ytp-ad-module', '.ytp-ad-overlay-container',
        '.ytp-ad-text-overlay', '#player-ads', '.ytp-ad-skip-button-slot',
        'ytd-display-ad-renderer', 'ytd-promoted-sparkles-web-renderer',
        'ytd-video-masthead-ad-renderer', 'ytd-banner-promo-renderer',
        '.ytd-ad-slot-renderer', 'ytd-in-feed-ad-layout-renderer',
        '.ytp-ad-progress-list', '.ytp-ad-duration-remaining'
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
      var adObserver = new MutationObserver(hideAds);
      adObserver.observe(document.body, { childList: true, subtree: true });
      
      setInterval(function() {
        var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern');
        if (skipBtn) skipBtn.click();
        
        var video = document.querySelector('video');
        var adModule = document.querySelector('.ytp-ad-module');
        if (adModule && video) {
          video.playbackRate = 16;
          setTimeout(function() { video.playbackRate = 1; }, 500);
        }
      }, 500);
    })();
  ''';

  static const String inlinePlaybackScript = '''
    (function() {
      'use strict';
      
      function setupVideoOverrides() {
        var videos = document.querySelectorAll('video');
        videos.forEach(function(video) {
          video.setAttribute('playsinline', 'true');
          video.setAttribute('webkit-playsinline', 'true');
          video.setAttribute('x5-playsinline', 'true');
          video.setAttribute('t7-video-player-type', 'inline');
          video.style.objectFit = 'contain';
          video.style.width = '100%';
          video.style.height = '100%';
        });
      }
      
      function blockFullscreen() {
        try {
          Object.defineProperty(HTMLVideoElement.prototype, 'requestFullscreen', {
            value: function() { return Promise.resolve(); },
            writable: false
          });
        } catch(e) {}
        
        try {
          Object.defineProperty(HTMLVideoElement.prototype, 'webkitRequestFullscreen', {
            value: function() {},
            writable: false
          });
        } catch(e) {}
        
        try {
          Object.defineProperty(HTMLVideoElement.prototype, 'webkitEnterFullScreen', {
            value: function() {},
            writable: false
          });
        } catch(e) {}
        
        try {
          Object.defineProperty(HTMLVideoElement.prototype, 'webkitEnterFullscreen', {
            value: function() {},
            writable: false
          });
        } catch(e) {}
        
        try {
          Object.defineProperty(HTMLVideoElement.prototype, 'mozRequestFullScreen', {
            value: function() {},
            writable: false
          });
        } catch(e) {}
        
        try {
          Object.defineProperty(HTMLVideoElement.prototype, 'msRequestFullscreen', {
            value: function() {},
            writable: false
          });
        } catch(e) {}
        
        try {
          Object.defineProperty(document, 'fullscreenEnabled', {
            value: false,
            writable: false
          });
          Object.defineProperty(document, 'webkitFullscreenEnabled', {
            value: false,
            writable: false
          });
        } catch(e) {}
      }
      
      function blockFullscreenEvents() {
        document.addEventListener('fullscreenchange', function(e) {
          if (document.fullscreenElement) {
            document.exitFullscreen().catch(function(){});
          }
        }, true);
        
        document.addEventListener('webkitfullscreenchange', function(e) {
          if (document.webkitFullscreenElement) {
            document.webkitExitFullscreen().catch(function(){});
          }
        }, true);
      }
      
      function blockDocumentFullscreen() {
        try {
          Object.defineProperty(document, 'requestFullscreen', {
            value: function() { return Promise.resolve(); },
            writable: false
          });
        } catch(e) {}
        
        try {
          Object.defineProperty(document, 'webkitRequestFullscreen', {
            value: function() {},
            writable: false
          });
        } catch(e) {}
      }
      
      setupVideoOverrides();
      blockFullscreen();
      blockFullscreenEvents();
      blockDocumentFullscreen();
      
      var videoObserver = new MutationObserver(function(mutations) {
        setupVideoOverrides();
        blockFullscreen();
      });
      
      if (document.body) {
        videoObserver.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
      }
    })();
  ''';

  static const String backgroundAudioScript = '''
    (function() {
      'use strict';
      
      var video = null;
      var wasPlaying = false;
      var audioCtx = null;
      var backgroundInterval = null;
      
      function findVideo() {
        video = document.querySelector('video');
        return video;
      }
      
      function createAudioContext() {
        try {
          var AudioContext = window.AudioContext || window.webkitAudioContext;
          if (AudioContext && !audioCtx) {
            audioCtx = new AudioContext();
            var oscillator = audioCtx.createOscillator();
            var gainNode = audioCtx.createGain();
            gainNode.gain.value = 0.001;
            oscillator.connect(gainNode);
            gainNode.connect(audioCtx.destination);
            oscillator.start();
          }
        } catch(e) {}
      }
      
      createAudioContext();
      
      try {
        var originalPause = HTMLMediaElement.prototype.pause;
        Object.defineProperty(HTMLMediaElement.prototype, 'pause', {
          value: function() {
            if (this === video && document.hidden) {
              return;
            }
            return originalPause.apply(this, arguments);
          },
          writable: true,
          configurable: true
        });
      } catch(e) {}
      
      try {
        var originalPlay = HTMLMediaElement.prototype.play;
        Object.defineProperty(HTMLMediaElement.prototype, 'play', {
          value: function() {
            if (audioCtx && audioCtx.state === 'suspended') {
              audioCtx.resume();
            }
            return originalPlay.apply(this, arguments);
          },
          writable: true,
          configurable: true
        });
      } catch(e) {}
      
      document.addEventListener('visibilitychange', function() {
        if (!video) findVideo();
        if (!video) return;
        
        if (document.hidden) {
          wasPlaying = !video.paused;
          if (wasPlaying) {
            if (audioCtx && audioCtx.state === 'suspended') {
              audioCtx.resume();
            }
            video.play().catch(function() {});
          }
        } else {
          if (audioCtx && audioCtx.state === 'suspended') {
            audioCtx.resume();
          }
        }
      });
      
      if (backgroundInterval) clearInterval(backgroundInterval);
      backgroundInterval = setInterval(function() {
        if (!video) findVideo();
        if (!video) return;
        
        if (document.hidden && wasPlaying && video.paused) {
          if (audioCtx && audioCtx.state === 'suspended') {
            audioCtx.resume();
          }
          video.play().catch(function() {});
        }
        
        if (!document.hidden && video.paused) {
          wasPlaying = false;
        }
      }, 200);
    })();
  ''';

  static const String pauseScript = '''
    (function() {
      var video = document.querySelector("video");
      if (video) video.pause();
    })();
  ''';

  static const String playScript = '''
    (function() {
      var video = document.querySelector("video");
      if (video) video.play();
    })();
  ''';

  static const String toggleScript = '''
    (function() {
      var video = document.querySelector("video");
      if (video) {
        if (video.paused) video.play(); else video.pause();
      }
    })();
  ''';
}
