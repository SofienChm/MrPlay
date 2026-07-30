class YouTubeJS {
  /// Blocks ads, prevents auto-play, forces unmute, and reports video state.
  static const String videoControlScript = '''
    (function() {
      // ── Config ──
      var AUTO_PLAY_PREVENTED = false;
      var VIDEO_UNMUTED = false;

      // ── Core functions ──

      function stopAutoplay() {
        if (AUTO_PLAY_PREVENTED) return;
        var videos = document.querySelectorAll("video");
        videos.forEach(function(v) {
          v.autoplay = false;
          if (!v.paused) {
            v.pause();
          }
        });
        AUTO_PLAY_PREVENTED = true;
      }

      function forceUnmute() {
        var videos = document.querySelectorAll("video");
        videos.forEach(function(v) {
          v.muted = false;
          v.volume = 1.0;
          v.defaultMuted = false;
        });
        VIDEO_UNMUTED = true;
      }

      function trapMuteChange() {
        try {
          var videos = document.querySelectorAll("video");
          videos.forEach(function(v) {
            v.muted = false;
            v.volume = 1.0;
            // Attempt to override muted setter (may fail in WKWebView)
            try {
              Object.defineProperty(HTMLMediaElement.prototype, 'muted', {
                get: function() { return false; },
                set: function(val) { /* ignore mute attempts */ },
                configurable: true
              });
            } catch(_) {}
          });
        } catch(_) {}
      }

      function reportState() {
        var video = document.querySelector("video");
        var titleEl = document.querySelector(
          'h1.title, .slim-video-information-title, ' +
          '.ytp-title, ytd-video-primary-info-renderer ' +
          'h1, #title h1'
        );
        var channelEl = document.querySelector(
          '.ytd-channel-name a, .slim-owner-channel-name a, ' +
          '#owner #channel-name a, ytd-video-owner-renderer a'
        );
        var title = titleEl ? titleEl.textContent.trim() : '';
        var channel = channelEl ? channelEl.textContent.trim() : '';

        try {
          window.videoState.postMessage(JSON.stringify({
            isPlaying: video ? !video.paused : false,
            currentTime: video ? video.currentTime : 0,
            duration: video ? video.duration : 0,
            title: title,
            channel: channel,
            thumbnail: ''
          }));
        } catch(e) {}
      }

      function enterMiniPlayer() {
        // Scroll down to trigger YouTube's native mini-player
        window.scrollBy(0, 250);
        // Also try to collapse the video if it's in fullscreen
        var video = document.querySelector("video");
        if (video) {
          if (document.webkitIsFullScreen || document.fullscreen) {
            document.webkitExitFullscreen();
          }
          // Attempt to use the WKWebView PiP API via native bridge
          try {
            video.webkitSetPresentationMode('picture-in-picture');
          } catch(e) {}
        }
      }

      function exitMiniPlayer() {
        // Scroll back up to show full video
        window.scrollTo(0, 0);
      }

      function isVideoActive() {
        var video = document.querySelector("video");
        return video && video.readyState >= 2 && !video.paused;
      }

      // ── Mutations ──

      function onMutation() {
        stopAutoplay();
        forceUnmute();
        if (VIDEO_UNMUTED) {
          trapMuteChange();
        }
      }

      // ── Run ──

      stopAutoplay();
      forceUnmute();
      trapMuteChange();
      reportState();

      // Watch DOM changes
      var observer = new MutationObserver(function() {
        onMutation();
        // Re-apply ad blocks
        var adSelectors = [
          '.video-ads', '.ytp-ad-module', '.ytp-ad-overlay-container',
          '.ytp-ad-text-overlay', '#player-ads', '.ytp-ad-skip-button-slot',
          'ytd-display-ad-renderer', 'ytd-promoted-sparkles-web-renderer',
          'ytd-video-masthead-ad-renderer', 'ytd-banner-promo-renderer',
          'ytd-in-feed-ad-layout-renderer', '.ytp-ad-progress-list',
          '.ytp-ad-duration-remaining'
        ];
        adSelectors.forEach(function(sel) {
          document.querySelectorAll(sel).forEach(function(el) {
            el.style.display = 'none';
            el.style.visibility = 'hidden';
            el.style.opacity = '0';
          });
        });
      });
      if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true });
      }

      // Auto-skip skippable ads
      setInterval(function() {
        var skipBtn = document.querySelector(
          '.ytp-ad-skip-button, .ytp-skip-ad-button'
        );
        if (skipBtn) skipBtn.click();

        var adModule = document.querySelector('.ytp-ad-module');
        var video = document.querySelector('video');
        if (adModule && video) {
          video.playbackRate = 16;
          setTimeout(function() { video.playbackRate = 1; }, 500);
        }
      }, 1000);

      // Report state every 500ms
      setInterval(reportState, 500);

      // Expose functions for Flutter to call
      window.__MrPlay = {
        enterMiniPlayer: enterMiniPlayer,
        exitMiniPlayer: exitMiniPlayer,
        isVideoActive: isVideoActive,
        forceUnmute: forceUnmute,
        pause: function() { var v = document.querySelector("video"); if(v) v.pause(); },
        play: function() { var v = document.querySelector("video"); if(v) v.play(); },
      };
    })();
  ''';

  static const String pauseScript = '''
    (function() {
      var v = document.querySelector("video");
      if (v) v.pause();
    })();
  ''';

  static const String playScript = '''
    (function() {
      var v = document.querySelector("video");
      if (v) v.play();
    })();
  ''';

  static const String enterMiniPlayerScript = '''
    (function() {
      if (window.__MrPlay && window.__MrPlay.enterMiniPlayer) {
        window.__MrPlay.enterMiniPlayer();
      }
    })();
  ''';

  static const String exitMiniPlayerScript = '''
    (function() {
      if (window.__MrPlay && window.__MrPlay.exitMiniPlayer) {
        window.__MrPlay.exitMiniPlayer();
      }
    })();
  ''';

  static const String isVideoActiveScript = '''
    (function() {
      if (window.__MrPlay && window.__MrPlay.isVideoActive) {
        return window.__MrPlay.isVideoActive();
      }
      var v = document.querySelector("video");
      return v ? (v.readyState >= 2 && !v.paused) : false;
    })();
  ''';

  static const String forceUnmuteScript = '''
    (function() {
      if (window.__MrPlay && window.__MrPlay.forceUnmute) {
        window.__MrPlay.forceUnmute();
      }
      var videos = document.querySelectorAll("video");
      videos.forEach(function(v) {
        v.muted = false;
        v.volume = 1.0;
      });
    })();
  ''';

  static const String seekScript = '''
    (function(time) {
      var video = document.querySelector("video");
      if (video) video.currentTime = time;
    })(%s);
  ''';
}
