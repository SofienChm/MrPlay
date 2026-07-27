class YouTubeJS {
  static const String adBlockScript = '''
    (function() {
      var adSelectors = [
        '.video-ads', '.ytp-ad-module', '.ytp-ad-overlay-container',
        '.ytp-ad-text-overlay', '#player-ads', '.ytp-ad-skip-button-slot',
        'ytd-display-ad-renderer', 'ytd-promoted-sparkles-web-renderer',
        'ytd-video-masthead-ad-renderer', 'ytd-banner-promo-renderer',
        '.ytd-ad-slot-renderer', 'ytd-in-feed-ad-layout-renderer',
        'ytd-ad-slot-renderer', '.ytp-ad-progress-list', '.ytp-ad-duration-remaining'
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
        var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button');
        if (skipBtn) skipBtn.click();
        
        var video = document.querySelector('video');
        var adModule = document.querySelector('.ytp-ad-module');
        if (adModule && video) {
          video.playbackRate = 16;
          setTimeout(function() { video.playbackRate = 1; }, 500);
        }
      }, 1000);
    })();
  ''';

  static const String inlinePlaybackScript = '''
    (function() {
      var meta = document.createElement('meta');
      meta.name = 'viewport';
      meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
      document.head.appendChild(meta);
      
      function setupVideos() {
        document.querySelectorAll('video').forEach(function(video) {
          video.setAttribute('playsinline', 'true');
          video.setAttribute('webkit-playsinline', 'true');
          video.style.objectFit = 'contain';
        });
      }
      
      setupVideos();
      var videoObserver = new MutationObserver(setupVideos);
      videoObserver.observe(document.body, { childList: true, subtree: true });
    })();
  ''';

  static const String backgroundAudioScript = '''
    (function() {
      'use strict';
      
      var video = null;
      var wasPlaying = false;
      var backgroundInterval = null;
      
      function findVideo() {
        video = document.querySelector('video');
        return video;
      }
      
      var originalPause = HTMLMediaElement.prototype.pause;
      HTMLMediaElement.prototype.pause = function() {
        if (this === video && document.hidden) {
          console.log('MrPlay: Blocked background pause');
          return Promise.resolve();
        }
        return originalPause.apply(this, arguments);
      };
      
      document.addEventListener('visibilitychange', function() {
        if (!video) findVideo();
        if (!video) return;
        
        if (document.hidden) {
          wasPlaying = !video.paused;
          if (wasPlaying) {
            video.play().catch(function(e) {
              console.log('MrPlay: Background play retry needed');
            });
          }
        } else {
          wasPlaying = false;
          if (backgroundInterval) {
            clearInterval(backgroundInterval);
            backgroundInterval = null;
          }
        }
      });
      
      backgroundInterval = setInterval(function() {
        if (!video) findVideo();
        if (!video) return;
        
        if (document.hidden && wasPlaying && video.paused) {
          console.log('MrPlay: Forcing background resume');
          video.play().catch(function(e) {});
        }
      }, 250);
      
      var AudioContext = window.AudioContext || window.webkitAudioContext;
      if (AudioContext) {
        var ctx = new AudioContext();
        document.addEventListener('visibilitychange', function() {
          if (document.hidden && ctx.state === 'suspended') {
            ctx.resume();
          }
        });
      }
      
      setInterval(function() {
        if (!video) findVideo();
        if (!video) return;
        
        var titleEl = document.querySelector('h1.title, .slim-video-information-title, .ytp-title');
        var channelEl = document.querySelector('.ytd-channel-name a, .slim-owner-channel-name a');
        var thumbEl = document.querySelector('.ytp-cued-thumbnail-overlay-image');
        
        var data = {
          isPlaying: !video.paused,
          currentTime: video.currentTime || 0,
          duration: video.duration || 0,
          title: titleEl ? titleEl.textContent.trim() : '',
          channel: channelEl ? channelEl.textContent.trim() : '',
          thumbnail: thumbEl ? thumbEl.style.backgroundImage : ''
        };
        
        if (window.videoState && window.videoState.postMessage) {
          window.videoState.postMessage(JSON.stringify(data));
        }
      }, 500);
    })();
  ''';

  static const String pauseScript = 'document.querySelector("video").pause();';
  static const String playScript = 'document.querySelector("video").play();';
}
