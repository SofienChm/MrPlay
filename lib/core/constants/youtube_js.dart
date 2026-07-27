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
      'use strict';
      
      var video = null;
      var originalRequestFullscreen = null;
      var originalWebkitRequestFullscreen = null;
      
      function setupVideoOverrides() {
        video = document.querySelector('video');
        if (!video) return;
        
        video.setAttribute('playsinline', 'true');
        video.setAttribute('webkit-playsinline', 'true');
        video.setAttribute('x5-playsinline', 'true');
        video.setAttribute('t7-video-player-type', 'inline');
        video.style.objectFit = 'contain';
        
        if (!originalRequestFullscreen) {
          originalRequestFullscreen = video.requestFullscreen;
        }
        if (!originalWebkitRequestFullscreen) {
          originalWebkitRequestFullscreen = video.webkitRequestFullscreen;
        }
        
        video.requestFullscreen = function() {
          console.log('MrPlay: Blocked requestFullscreen');
          return Promise.resolve();
        };
        
        video.webkitRequestFullscreen = function() {
          console.log('MrPlay: Blocked webkitRequestFullscreen');
          return;
        };
        
        video.webkitEnterFullScreen = function() {
          console.log('MrPlay: Blocked webkitEnterFullScreen');
          return;
        };
        
        video.webkitExitFullScreen = function() {
          console.log('MrPlay: Blocked webkitExitFullScreen');
          return;
        };
        
        video.addEventListener('click', function(e) {
          if (video.webkitDisplayingFullscreen) {
            e.preventDefault();
            e.stopPropagation();
          }
        }, true);
      }
      
      setupVideoOverrides();
      
      var videoObserver = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
          mutation.addedNodes.forEach(function(node) {
            if (node.tagName === 'VIDEO') {
              setupVideoOverrides();
            }
          });
        });
      });
      
      if (document.body) {
        videoObserver.observe(document.body, { childList: true, subtree: true });
      } else {
        document.addEventListener('DOMContentLoaded', function() {
          videoObserver.observe(document.body, { childList: true, subtree: true });
        });
      }
      
      document.requestFullscreen = function() {
        console.log('MrPlay: Blocked document.requestFullscreen');
        return Promise.resolve();
      };
      
      document.webkitRequestFullscreen = function() {
        console.log('MrPlay: Blocked document.webkitRequestFullscreen');
        return;
      };
    })();
  ''';

  static const String backgroundAudioScript = '''
    (function() {
      'use strict';
      
      var video = null;
      var wasPlaying = false;
      var backgroundInterval = null;
      var audioCtx = null;
      
      function findVideo() {
        video = document.querySelector('video');
        return video;
      }
      
      function createAudioContext() {
        var AudioContext = window.AudioContext || window.webkitAudioContext;
        if (AudioContext) {
          audioCtx = new AudioContext();
          
          var oscillator = audioCtx.createOscillator();
          var gainNode = audioCtx.createGain();
          gainNode.gain.value = 0.001;
          oscillator.connect(gainNode);
          gainNode.connect(audioCtx.destination);
          oscillator.start();
          
          setInterval(function() {
            if (audioCtx.state === 'suspended') {
              audioCtx.resume();
            }
          }, 1000);
        }
      }
      
      createAudioContext();
      
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
            if (audioCtx && audioCtx.state === 'suspended') {
              audioCtx.resume();
            }
            video.play().catch(function(e) {
              console.log('MrPlay: Background play retry needed');
            });
          }
        } else {
          wasPlaying = false;
        }
      });
      
      backgroundInterval = setInterval(function() {
        if (!video) findVideo();
        if (!video) return;
        
        if (document.hidden && wasPlaying && video.paused) {
          console.log('MrPlay: Forcing background resume');
          if (audioCtx && audioCtx.state === 'suspended') {
            audioCtx.resume();
          }
          video.play().catch(function(e) {});
        }
      }, 250);
      
      setInterval(function() {
        if (!video) findVideo();
        if (!video) return;
        
        var titleEl = document.querySelector('h1.title, .slim-video-information-title, .ytp-title, #title h1');
        var channelEl = document.querySelector('.ytd-channel-name a, .slim-owner-channel-name a, #text a');
        var thumbEl = document.querySelector('.ytp-cued-thumbnail-overlay-image, .html5-main-video');
        
        var data = {
          isPlaying: !video.paused,
          currentTime: video.currentTime || 0,
          duration: video.duration || 0,
          title: titleEl ? titleEl.textContent.trim().substring(0, 100) : '',
          channel: channelEl ? channelEl.textContent.trim().substring(0, 100) : '',
          thumbnail: thumbEl ? (thumbEl.style.backgroundImage || '') : ''
        };
        
        if (window.videoState && window.videoState.postMessage) {
          window.videoState.postMessage(JSON.stringify(data));
        }
      }, 500);
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
}
