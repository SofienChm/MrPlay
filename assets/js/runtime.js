// MrPlay page runtime. Injected at document start into every frame-0 page.
// Single home for every "<video> command" the app sends, so Dart calls
// short one-liners like `window.__mr.play()` instead of shipping JS strings.
(function () {
  if (window.__mr) return;

  function bridge(name, payload) {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler(name, payload);
      }
    } catch (e) {}
  }

  // The actively-playing <video>, falling back to YouTube's main player and
  // then the first element, so controls never target a stale ad/preview.
  function activeVideo() {
    var videos = document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      if (!videos[i].paused && !videos[i].ended) return videos[i];
    }
    var main = document.querySelector('#movie_player video, .html5-video-player video');
    if (main) return main;
    return videos.length > 0 ? videos[0] : null;
  }

  function moviePlayer() {
    try { return document.getElementById('movie_player'); } catch (e) { return null; }
  }

  function isAdShowing(v) {
    try {
      var p = v && v.closest ? v.closest('.html5-video-player') : null;
      if (!p) p = document.querySelector('.html5-video-player');
      return !!(p && p.classList.contains('ad-showing'));
    } catch (e) { return false; }
  }

  function state(v) {
    v = v || activeVideo();
    if (!v) return null;
    var pipMode = false;
    var pipActive = false;
    try {
      pipMode = typeof v.webkitPresentationMode !== 'undefined' &&
        v.webkitPresentationMode === 'picture-in-picture';
      pipActive = !!document.pictureInPictureElement;
    } catch (e) {}
    return {
      playing: !v.paused && !v.ended && v.playbackRate > 0,
      position: isFinite(v.currentTime) ? v.currentTime : 0,
      duration: isFinite(v.duration) ? v.duration : 0,
      ended: !!v.ended,
      muted: !!v.muted,
      adShowing: isAdShowing(v),
      pip: pipMode || pipActive,
      pipActive: pipActive,
      pipStuck: pipMode && !pipActive,
      buffering: !v.ended && v.readyState < 3
    };
  }

  function report(v) {
    var s = state(v);
    if (s) bridge('videoState', s);
  }

  // Background "soft pause": a paused <video> in a backgrounded page loses
  // its PiP session. Freezing it at playbackRate 0 keeps the page alive.
  function softResume() {
    var s = window.__mrSoftPaused;
    if (!s) return;
    window.__mrSoftPaused = null;
    try { s.el.playbackRate = s.rate || 1; } catch (e) {}
  }

  function softPauseToReal() {
    var s = window.__mrSoftPaused;
    if (!s) return;
    window.__mrSoftPaused = null;
    try { s.el.pause(); s.el.playbackRate = s.rate || 1; } catch (e) {}
  }

  function play() {
    window.__mrUserPaused = false;
    softResume();
    var v = activeVideo();
    if (v && v.paused) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
  }

  var pauseGuardInstalled = false;
  function pause() {
    // Tells an in-flight phantom-PiP handoff not to restart the video; any
    // real playback clears it again.
    window.__mrUserPaused = true;
    if (!pauseGuardInstalled) {
      pauseGuardInstalled = true;
      document.addEventListener('playing', function () { window.__mrUserPaused = false; }, true);
    }
    var v = activeVideo();
    if (v) v.pause();
  }

  function seek(seconds) {
    var v = activeVideo();
    if (v) { try { v.currentTime = seconds; } catch (e) {} }
  }

  // Resumes a paused video, replays an ended one from the start.
  function resumeOrStart() {
    var v = activeVideo();
    if (!v) return;
    if (v.ended) { try { v.currentTime = 0; } catch (e) {} }
    if (v.paused) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
  }

  // Un-mutes the active video and unlocks YouTube's player, but never while an
  // ad shows (the ad blocker owns the mute then).
  function unmute() {
    var v = activeVideo();
    if (!v) return { audible: false };
    if (!v.muted && v.volume > 0) return { audible: true };
    var player = moviePlayer();
    if (isAdShowing(v)) return { audible: false };
    v.muted = false;
    v.defaultMuted = false;
    v.volume = 1;
    try {
      if (player) {
        if (typeof player.unMute === 'function') player.unMute();
        else if (typeof player.setVolume === 'function') player.setVolume(100);
      }
    } catch (e) {}
    try {
      var btn = player && player.querySelector('.ytp-unmute-widget button, [class*="unmute"] button');
      if (btn && typeof btn.click === 'function') btn.click();
    } catch (e) {}
    return { audible: !v.muted && v.volume > 0 };
  }

  function toggleCaptions() {
    var v = activeVideo();
    if (!v || !v.textTracks || v.textTracks.length === 0) return;
    var shown = false;
    for (var i = 0; i < v.textTracks.length; i++) {
      if (v.textTracks[i].mode === 'showing') { shown = true; break; }
    }
    for (var j = 0; j < v.textTracks.length; j++) {
      v.textTracks[j].mode = shown ? 'hidden' : 'showing';
    }
  }

  function fullscreen(mode) {
    var v = activeVideo();
    if (mode === 'exit') {
      if (document.fullscreenElement && document.exitFullscreen) {
        document.exitFullscreen().catch(function () {});
      }
      if (v && v.webkitExitFullscreen) { try { v.webkitExitFullscreen(); } catch (e) {} }
      return;
    }
    if (!v) return;
    if (v.requestFullscreen) {
      if (document.fullscreenElement) {
        if (mode === 'toggle') document.exitFullscreen().catch(function () {});
      } else {
        v.requestFullscreen().catch(function () {});
      }
    } else if (v.webkitEnterFullscreen) {
      try { v.webkitEnterFullscreen(); } catch (e) {}
    }
  }

  function togglePip() {
    var v = activeVideo();
    if (!v) return;
    if (v.requestPictureInPicture) {
      if (document.pictureInPictureElement) document.exitPictureInPicture().catch(function () {});
      else v.requestPictureInPicture().catch(function () {});
    } else if (v.webkitSetPresentationMode) {
      v.webkitSetPresentationMode(
        v.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture');
    }
  }

  function enterPip() {
    var v = activeVideo();
    if (!v) return;
    if (v.requestPictureInPicture) v.requestPictureInPicture().catch(function () {});
    else if (v.webkitSetPresentationMode && v.webkitPresentationMode !== 'picture-in-picture') {
      v.webkitSetPresentationMode('picture-in-picture');
    }
  }

  function exitPip() {
    var v = activeVideo();
    if (!v) return;
    if (document.exitPictureInPicture && document.pictureInPictureElement) {
      document.exitPictureInPicture().catch(function () {});
    } else if (v.webkitSetPresentationMode && v.webkitPresentationMode === 'picture-in-picture') {
      v.webkitSetPresentationMode('inline');
    }
  }

  // Un-sticks a <video> left in PiP presentation mode with no PiP window
  // (renders black inline). Never touches a real PiP window.
  function forceInline() {
    var v = activeVideo();
    if (!v || !v.webkitSetPresentationMode) return;
    if (v.webkitPresentationMode !== 'picture-in-picture') return;
    if (document.pictureInPictureElement) return;
    try { v.webkitSetPresentationMode('inline'); } catch (e) {}
  }

  function waitForMode(v, mode, timeoutMs) {
    return new Promise(function (resolve) {
      var done = false;
      function finish(ok) {
        if (done) return;
        done = true;
        clearTimeout(timer);
        v.removeEventListener('webkitpresentationmodechanged', onMode);
        resolve(ok);
      }
      function onMode() { if (v.webkitPresentationMode === mode) finish(true); }
      var timer = setTimeout(function () { finish(false); }, timeoutMs);
      v.addEventListener('webkitpresentationmodechanged', onMode);
      try { v.webkitSetPresentationMode(mode); } catch (e) { finish(false); }
    });
  }

  // Phantom PiP: hands the video to a PiP/AVFoundation session on background
  // so iOS keeps the audio alive, then makes sure it is actually playing.
  // `userPlay` marks an explicit lock-screen play (must come back audible).
  async function enterPhantomPip(userPlay) {
    if (userPlay) { window.__mrUserPaused = false; softResume(); }
    var v = activeVideo();
    if (!v || !v.webkitSetPresentationMode) return { ok: false, reason: 'no-video' };
    try { v.disablePictureInPicture = false; v.removeAttribute('disablepictureinpicture'); } catch (e) {}
    if (v.webkitPresentationMode !== 'picture-in-picture') {
      await waitForMode(v, 'picture-in-picture', 1500);
    }
    if (window.__mrUserPaused === true) return { ok: true, reason: 'user-paused' };
    if (v.paused) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try { await v.play(); break; } catch (e) {
          if (attempt === 1) return { ok: false, reason: 'play-rejected' };
          await new Promise(function (r) { setTimeout(r, 200); });
        }
      }
    }
    if (userPlay && !v.paused && v.muted && !isAdShowing(v)) {
      v.muted = false;
      var mp = moviePlayer();
      try { if (mp && typeof mp.unMute === 'function') mp.unMute(); } catch (e) {}
    }
    return { ok: !v.paused, reason: v.paused ? 'still-paused' : 'playing' };
  }

  // Re-asserts phantom PiP without resuming a video the user paused, so the
  // WebContent process stays reachable for a later lock-screen play.
  function reassertPhantomPip() {
    var v = activeVideo();
    if (!v || !v.webkitSetPresentationMode) return;
    if (v.webkitPresentationMode === 'picture-in-picture') return;
    if (window.__mrUserPaused === true) {
      var hold = function () { if (window.__mrUserPaused === true) v.pause(); };
      v.addEventListener('play', hold);
      setTimeout(function () { v.removeEventListener('play', hold); }, 3000);
    }
    try { v.webkitSetPresentationMode('picture-in-picture'); } catch (e) {}
  }

  // Brings a phantom-PiP'd video back inline on resume. A real user PiP
  // window is left alone.
  async function restoreInline() {
    var v = activeVideo();
    if (!v) return { ok: true, reason: 'no-video' };
    if (document.pictureInPictureElement) return { ok: true, reason: 'real-pip' };
    if (!v.webkitSetPresentationMode || v.webkitPresentationMode !== 'picture-in-picture') {
      return { ok: true, reason: 'already-inline' };
    }
    var ok = await waitForMode(v, 'inline', 1500);
    if (!ok) return { ok: false, reason: 'timeout' };
    var rendered = v.videoWidth > 0;
    return { ok: rendered, reason: rendered ? 'inline' : 'no-render' };
  }

  function nudge(play) {
    var v = activeVideo();
    if (!v) return;
    try { v.currentTime = v.currentTime; } catch (e) {}
    if (play) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
  }

  function airplay() {
    var v = activeVideo();
    if (v && v.webkitShowPlaybackTargetPicker) v.webkitShowPlaybackTargetPicker();
  }

  // Reads the watch-page title for the mini player. Returns true once
  // reported (or when the page is no longer a watch page).
  function reportWatchInfo() {
    if (location.pathname.indexOf('/watch') === -1) return true;
    var el = document.querySelector('h1.title, .slim-video-information-title, .ytp-title, #title h1');
    var m = location.search.match(/[?&]v=([^&]+)/);
    var title = el ? el.textContent.trim().substring(0, 200) : '';
    if (!title) return false;
    bridge('playerInfo', {
      id: m ? m[1] : '',
      title: title,
      thumbnailUrl: m ? 'https://i.ytimg.com/vi/' + m[1] + '/hqdefault.jpg' : '',
      videoUrl: location.href,
      platform: 'YouTube'
    });
    return true;
  }

  window.__mr = {
    bridge: bridge,
    activeVideo: activeVideo,
    state: state,
    report: report,
    play: play,
    pause: pause,
    seek: seek,
    resumeOrStart: resumeOrStart,
    unmute: unmute,
    softPauseToReal: softPauseToReal,
    toggleCaptions: toggleCaptions,
    fullscreen: fullscreen,
    togglePip: togglePip,
    enterPip: enterPip,
    exitPip: exitPip,
    forceInline: forceInline,
    enterPhantomPip: enterPhantomPip,
    reassertPhantomPip: reassertPhantomPip,
    restoreInline: restoreInline,
    nudge: nudge,
    airplay: airplay,
    reportWatchInfo: reportWatchInfo
  };
})();
