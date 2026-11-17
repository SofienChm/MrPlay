import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/feature_flags.dart';
import '../../core/utils/log.dart';
import '../../core/utils/url_utils.dart';
import '../../data/models/models.dart';
import '../../data/repositories/settings_repository.dart';
import '../browser/browser_state.dart';
import '../browser/web_policy.dart';
import '../browser/web_scripts.dart';
import 'playback_policy.dart';
import 'player_state.dart';
import 'video_bridge.dart';

/// Overridden at startup with the scripts loaded from assets.
final webScriptsProvider = Provider<WebScripts>(
  (ref) => throw UnimplementedError('webScriptsProvider must be overridden'),
);

final playbackEngineProvider = Provider<PlaybackEngine>((ref) {
  final engine = PlaybackEngine(ref);
  ref.onDispose(engine.dispose);
  return engine;
});

/// The single owner of playback and in-app browsing.
///
/// Widgets only render [playerProvider] / [browserProvider] and call this
/// class. It drives the two webviews (browse tab + YouTube video tab), keeps
/// audio alive in the background (phantom PiP for video, a silent loop for
/// YouTube Music), survives interruptions, and advances the queue — in the
/// foreground and the background.
class PlaybackEngine with WidgetsBindingObserver {
  PlaybackEngine(this._ref) : scripts = _ref.read(webScriptsProvider) {
    video = VideoBridge(() => _activeController);
    WidgetsBinding.instance.addObserver(this);
    _ref.read(nowPlayingProvider).listen(_onNativeCommand);
    _settings = _ref.read(settingsProvider);
    _ref.listen(settingsProvider, (prev, next) => _onSettingsChanged(next));
    unawaited(_subscribeToInterruptions());
  }

  final Ref _ref;
  final WebScripts scripts;
  late final VideoBridge video;

  late AppSettings _settings;

  InAppWebViewController? _browse;
  InAppWebViewController? _video;
  String? _pendingBrowseUrl;

  // Lifecycle -------------------------------------------------------------
  bool _backgrounded = false;
  bool _inactive = false;
  DateTime? _pausedAt;

  // Background session ----------------------------------------------------
  /// A system-forced pause of Music may be auto-resumed in the background.
  bool _backgroundResumeAllowed = false;
  bool _userPaused = false;
  DateTime _userPausedAt = _epoch;
  /// The video stopped on its own while backgrounded (route loss, stalled
  /// autoplay...): keep the webview reachable for a lock-screen play.
  bool _stoppedUnexpectedly = false;
  /// Latched when the system took the audio (call / another app). While set,
  /// state reports can't flip Now Playing back to "playing".
  bool _systemPaused = false;
  Duration _systemPausedAt = Duration.zero;
  bool _isMusic = false;
  /// The queue advanced in the background and the next video hasn't started.
  bool _handoffPending = false;
  bool _endedHandled = false;

  // Throttles & timestamps -------------------------------------------------
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastUnmuteAttempt = _epoch;
  DateTime _lastPlayStart = _epoch;
  DateTime _lastKnownPlaying = _epoch;
  DateTime? _pipStuckSince;
  DateTime _lastInlineForce = _epoch;
  DateTime _lastPopupAllowed = _epoch;
  DateTime _lastProcessRecovery = _epoch;
  DateTime _lastSeekDragTick = _epoch;
  bool _wasPlayingAtSeek = false;
  int _lastNowPlayingMs = 0;
  bool? _lastNowPlayingPlaying;
  bool _goingBack = false;

  Timer? _statePoll;
  Timer? _pausedKeepAlive;
  Timer? _remoteSeekResume;
  Timer? _loadingTimer;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;

  PlayerState get _player => _ref.read(playerProvider);
  PlayerNotifier get _playerN => _ref.read(playerProvider.notifier);
  BrowserState get _browser => _ref.read(browserProvider);
  void _setBrowser(BrowserState Function(BrowserState s) change) =>
      _ref.read(browserProvider.notifier).set(change);

  InAppWebViewController? get _activeController => _video ?? _browse;

  bool get isPlaying => _player.isPlaying;

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in [_statePoll, _pausedKeepAlive, _remoteSeekResume, _loadingTimer]) {
      t?.cancel();
    }
    unawaited(_interruptions?.cancel());
    unawaited(_ref.read(statsRepositoryProvider).flush());
    unawaited(_ref.read(keepAliveAudioProvider).stop());
  }

  // =====================================================================
  // Navigation API
  // =====================================================================

  /// Opens [url] in the browser layer. YouTube watch pages go to the video
  /// tab; YouTube Music closes any video tab so only one thing plays.
  void loadUrl(String url) {
    if (UrlUtils.isMusic(url) && _browser.hasVideoTab) closePlayer();
    if (UrlUtils.routesToVideoTab(url)) {
      _loadingTimer?.cancel();
      _setBrowser((s) => s.copyWith(visible: true, pageLoading: false));
      _openVideoTab(url);
      return;
    }
    _lastUnmuteAttempt = _epoch;
    _setBrowser(
      (s) => s.copyWith(
        visible: true,
        browseUrl: url,
        pageLoading: true,
        platformLoading: true,
        clearError: true,
      ),
    );
    final c = _browse;
    if (c != null) {
      unawaited(c.loadUrl(urlRequest: URLRequest(url: WebUri(url))));
    } else {
      _pendingBrowseUrl = url;
    }
    _armLoadingTimeout();
  }

  /// Plays items one after the other: the first now, the rest queued.
  Future<void> playSequentially(List<MediaItem> items) async {
    if (items.isEmpty) return;
    await _ref.read(queueRepositoryProvider).replaceAll(items.skip(1).toList());
    loadUrl(items.first.url);
  }

  /// Full reset back to the hub: stops playback, closes both tabs.
  void goHub() {
    _teardownPlayback();
    final browse = _browse;
    _browse = null;
    unawaited(browse?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank'))));
    _setBrowser((s) => const BrowserState());
  }

  void retry() {
    _setBrowser((s) => s.copyWith(clearError: true, platformLoading: true));
    unawaited(_browse?.reload());
  }

  void minimizeVideoTab() {
    if (_browser.hasVideoTab) _playerN.minimize();
  }

  void expand() {
    unawaited(video.exitPip());
    _playerN.expand();
  }

  /// Floating "mini player" button: track what plays and collapse.
  void showMiniPlayer() {
    _trackFromUrl();
    if (_player.hasVideo) _playerN.minimize();
  }

  void _openVideoTab(String url) {
    if (_browser.videoTabUrl == url) return;
    _lastUnmuteAttempt = _epoch;
    _lastPlayStart = DateTime.now();
    _playerN.markVideoTab();
    final c = _video;
    if (c != null) {
      _setBrowser((s) => s.copyWith(videoTabUrl: url));
      unawaited(c.loadUrl(urlRequest: URLRequest(url: WebUri(url))));
    } else {
      _setBrowser((s) => s.copyWith(videoTabUrl: url, videoTabId: s.videoTabId + 1));
    }
  }

  void _armLoadingTimeout() {
    _loadingTimer?.cancel();
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      _setBrowser((s) => s.copyWith(pageLoading: false));
    });
  }

  // =====================================================================
  // Playback API (mini player, full player, sleep timer, remote commands)
  // =====================================================================

  void togglePlay() => isPlaying ? pause() : resume();

  /// Explicit user pause. In the background the webview is kept reachable so
  /// a later lock-screen play still works.
  void pause({bool pageHandled = false}) {
    _backgroundResumeAllowed = false;
    _lastKnownPlaying = _epoch;
    _userPaused = true;
    _userPausedAt = DateTime.now();
    _stoppedUnexpectedly = false;
    _handoffPending = false;
    _wasPlayingAtSeek = false;
    final keepAlive = _ref.read(keepAliveAudioProvider);
    if (!_backgrounded) {
      unawaited(keepAlive.stop());
      _stopPausedKeepAlive();
    } else if (_settings.backgroundAudio && !_systemPaused) {
      // Pausing ends the phantom-PiP session, which lets iOS suspend the
      // webview; keep it alive so Control Center play can reach it.
      unawaited(keepAlive.start());
      _startPausedKeepAlive();
    }
    _playerN.setPlaying(false);
    if (!pageHandled) unawaited(video.pause());
    _lastNowPlayingPlaying = false;
    unawaited(
      _ref.read(nowPlayingProvider).setProgress(
            position: _player.position,
            duration: _player.duration,
            isPlaying: false,
          ),
    );
  }

  /// Explicit user resume; clears the system-pause latch.
  void resume({bool pageHandled = false}) {
    _systemPaused = false;
    _systemPausedAt = Duration.zero;
    _lastPlayStart = DateTime.now();
    _lastKnownPlaying = DateTime.now();
    _backgroundResumeAllowed = true;
    _userPaused = false;
    _handoffPending = false;
    _stoppedUnexpectedly = false;
    _stopPausedKeepAlive();
    _playerN.setPlaying(true);
    if (_backgrounded && _settings.backgroundAudio) {
      unawaited(_resumeFromBackground());
    } else if (!pageHandled) {
      unawaited(video.play());
    }
    // YouTube can re-mute a script-resumed video.
    _lastUnmuteAttempt = _epoch;
    for (final ms in const [400, 1200]) {
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (!_userPaused) unawaited(video.unmute());
      });
    }
  }

  void seekTo(Duration target) {
    final t = PlaybackPolicy.clampSeek(target, _player.duration);
    _playerN.seekTo(t);
    unawaited(video.seek(t));
  }

  void seekBy(Duration delta) => seekTo(_player.position + delta);

  /// Closes the player (video tab included) but stays in the browser.
  void closePlayer() {
    _teardownPlayback();
    _setBrowser((s) => s.copyWith(clearVideoTab: true));
  }

  void togglePip() => unawaited(video.togglePip());
  void enterPip() => unawaited(video.enterPip());
  void exitPip() => unawaited(video.exitPip());
  void toggleCaptions() => unawaited(video.toggleCaptions());
  void toggleFullscreen() => unawaited(video.toggleFullscreen());
  void airplay() => unawaited(video.airplay());

  void onOrientationChanged({required bool landscape}) {
    if (!_settings.fullscreenOnRotation || !_player.hasVideo) return;
    if (landscape) {
      if (_player.isVideoTab && _player.isMinimized) _playerN.expand();
      if (!_player.isMinimized) unawaited(video.enterFullscreen());
    } else {
      unawaited(video.exitFullscreen());
    }
  }

  void _teardownPlayback() {
    unawaited(video.pause());
    unawaited(_ref.read(keepAliveAudioProvider).stop());
    _systemPaused = false;
    _systemPausedAt = Duration.zero;
    _stopStatePoll();
    _stopPausedKeepAlive();
    _loadingTimer?.cancel();
    _video = null;
    unawaited(_ref.read(statsRepositoryProvider).flush());
    unawaited(_ref.read(nowPlayingProvider).clear());
    _playerN.dismiss();
  }

  // =====================================================================
  // Webview wiring (called by BrowserLayer)
  // =====================================================================

  void onWebViewCreated(WebTab tab, InAppWebViewController c) {
    if (tab == WebTab.browse) {
      _browse = c;
      final pending = _pendingBrowseUrl;
      _pendingBrowseUrl = null;
      if (pending != null) unawaited(c.loadUrl(urlRequest: URLRequest(url: WebUri(pending))));
    } else {
      _video = c;
      // initialUrlRequest already started the load; only re-navigate if the
      // video was replaced while the tab was being created.
    }
    _registerHandlers(c);
  }

  void _registerHandlers(InAppWebViewController c) {
    Map<String, dynamic>? payload(List<dynamic> args) =>
        args.isNotEmpty && args.first is Map ? Map<String, dynamic>.from(args.first as Map) : null;

    c.addJavaScriptHandler(
      handlerName: 'playerInfo',
      callback: (args) {
        final data = payload(args);
        if (data != null && _accepts(c)) _onPlayerInfo(data);
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'videoState',
      callback: (args) {
        final data = payload(args);
        if (data != null && _accepts(c)) _onVideoState(data);
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'playerControl',
      callback: (args) {
        if (!_accepts(c)) return;
        switch (payload(args)?['action']) {
          case 'toggleCaptions':
            toggleCaptions();
          case 'pip':
            togglePip();
          case 'fullscreen':
            toggleFullscreen();
        }
      },
    );
    // Lock-screen play/pause already applied by the page (trusted WebKit
    // remote command): only sync our state and the background keep-alive.
    c.addJavaScriptHandler(
      handlerName: 'mediaCommand',
      callback: (args) {
        if (!_accepts(c)) return;
        final action = payload(args)?['action'];
        log('page media command=$action bg=$_backgrounded', tag: 'lock');
        if (action == 'pause') pause(pageHandled: true);
        if (action == 'play') resume(pageHandled: true);
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'videoTabSwipe',
      callback: (_) {
        if (_accepts(c)) minimizeVideoTab();
      },
    );
  }

  /// Player events only count from the webview that owns playback.
  bool _accepts(InAppWebViewController source) =>
      identical(source, _browser.hasVideoTab ? _video : _browse);

  void onLoadStart(WebTab tab, String? url) {
    if (url == null) return;
    if (tab == WebTab.video) {
      if (UrlUtils.routesToVideoTab(url) && url != _browser.videoTabUrl) _openVideoTab(url);
      return;
    }
    _setBrowser((s) => s.copyWith(browseUrl: url, pageLoading: true, clearError: true));
    _armLoadingTimeout();
  }

  void onLoadStop(WebTab tab, InAppWebViewController c, String? url) {
    _loadingTimer?.cancel();
    _setBrowser((s) => s.copyWith(pageLoading: false, platformLoading: false));
    if (url == null) return;
    if (tab == WebTab.browse && UrlUtils.routesToVideoTab(url) && url != _browser.videoTabUrl) {
      _openVideoTab(url);
      return;
    }
    _handleWatchPage(c, url);
  }

  /// YouTube is a single-page app: video navigations come through history
  /// updates, not page loads.
  void onVisitedHistory(WebTab tab, InAppWebViewController c, String? url) {
    if (url == null) return;
    if (tab == WebTab.video) {
      if (url.contains('youtube.com') && url.contains('/watch')) {
        if (url != _browser.videoTabUrl) {
          _setBrowser((s) => s.copyWith(videoTabUrl: url));
          _trackPlaceholder(url);
        }
        _handleWatchPage(c, url);
      }
      return;
    }
    _setBrowser((s) => s.copyWith(browseUrl: url));
    if (UrlUtils.routesToVideoTab(url)) {
      // Move the watch page into the video tab and step the feed back.
      _openVideoTab(url);
      if (_goingBack) return;
      _goingBack = true;
      Future<void>.delayed(const Duration(milliseconds: 80), () async {
        _goingBack = false;
        try {
          await c.goBack();
        } on Exception catch (e) {
          log('goBack failed: $e');
        }
      });
      return;
    }
    if (UrlUtils.isMusic(url) && url.contains('/watch') && _browser.hasVideoTab) closePlayer();
    _handleWatchPage(c, url);
  }

  void onMainFrameError(String message) {
    _setBrowser((s) => s.copyWith(platformLoading: false, error: message));
  }

  NavigationActionPolicy shouldOverrideUrlLoading(WebUri? url) => WebPolicy.allowNavigation(
        scheme: url?.scheme.toLowerCase(),
        host: url?.host,
        blockAdDomains: _settings.blockPopups,
      )
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL;

  /// New-window requests open in the same webview (popups filtered first).
  bool onCreateWindow(InAppWebViewController c, CreateWindowAction action) {
    final url = action.request.url;
    if (url == null) return true;
    if (_settings.blockPopups) {
      final ok = WebPolicy.allowPopup(
        host: url.host,
        sinceLastAllowed: DateTime.now().difference(_lastPopupAllowed),
      );
      if (!ok) return true;
      _lastPopupAllowed = DateTime.now();
    }
    unawaited(c.loadUrl(urlRequest: URLRequest(url: url)));
    return true;
  }

  /// iOS killed the WebContent process (memory pressure): reload the page,
  /// rate-limited so a crashing page can't loop. Not in the background.
  Future<void> onProcessTerminated(WebTab tab, InAppWebViewController c) async {
    if (_backgrounded) return;
    final now = DateTime.now();
    if (now.difference(_lastProcessRecovery) < const Duration(seconds: 5)) return;
    _lastProcessRecovery = now;
    final url = tab == WebTab.video ? _browser.videoTabUrl : _browser.browseUrl;
    log('web content process terminated ($tab), reloading');
    try {
      if (url != null && url.isNotEmpty) {
        await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      } else {
        await c.reload();
      }
    } on Exception catch (e) {
      log('process recovery failed: $e');
    }
    if (tab == WebTab.video) {
      Future<void>.delayed(const Duration(milliseconds: 1500), video.resumeOrStart);
    }
  }

  /// Re-injects the swipe-to-collapse listeners after a collapse cycle
  /// (WKWebView can drop the page's touch handlers).
  void onVideoTabExpanded() {
    Future<void>.delayed(const Duration(milliseconds: 400), () async {
      try {
        await _video?.evaluateJavascript(source: scripts.videoTab);
      } on Exception catch (e) {
        log('swipe script reinjection failed: $e');
      }
    });
  }

  void _handleWatchPage(InAppWebViewController c, String url) {
    if (url.contains('youtube.com') && url.contains('/watch')) unawaited(_reportWatchInfo(c));
  }

  /// The title element may not be rendered yet, so retry a few times.
  Future<void> _reportWatchInfo(InAppWebViewController c) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      await Future<void>.delayed(Duration(milliseconds: attempt == 0 ? 1500 : 2000));
      if (await video.reportWatchInfo(c)) return;
    }
  }

  // =====================================================================
  // Page events
  // =====================================================================

  void _onPlayerInfo(Map<String, dynamic> data) {
    final title = data['title'] as String? ?? '';
    if (title.isEmpty) return;
    final info = Video(
      id: data['id'] as String? ?? '',
      title: title,
      url: data['videoUrl'] as String? ?? '',
      thumbnailUrl: data['thumbnailUrl'] as String? ?? '',
      platform: data['platform'] as String? ?? 'YouTube',
    );
    final current = _player.video;
    if (current?.id != info.id) {
      _resetForNewVideo(info.url);
      if (current == null) {
        _startTracking(info);
      } else {
        _playerN.updateMetadata(info);
        _onTrackChanged(info);
      }
    } else if (current != null && current.hasPlaceholderTitle) {
      _playerN.updateMetadata(info);
      unawaited(_ref.read(historyRepositoryProvider).updateTitle(info.url, info.title));
      _indexInSpotlight(info);
      unawaited(_ref.read(nowPlayingProvider).setTrack(title: info.title, artist: info.platform, artworkUrl: info.thumbnailUrl));
    }
  }

  void _onVideoState(Map<String, dynamic> data) {
    final playing = data['playing'] == true;
    final adShowing = data['adShowing'] == true;
    final ended = PlaybackPolicy.isRealEnd(ended: data['ended'] == true, adShowing: adShowing);

    // A video restarting by itself shortly after a background user pause
    // (late phantom-PiP play, the page's own autoplay) is undone.
    if (playing &&
        !ended &&
        _backgrounded &&
        _userPaused &&
        DateTime.now().difference(_userPausedAt) < PlaybackPolicy.userPauseGuard) {
      unawaited(video.pause());
      return;
    }

    if (playing && !ended) {
      _lastKnownPlaying = DateTime.now();
      _stopPausedKeepAlive();
      _stoppedUnexpectedly = false;
      _handoffPending = false;
      _endedHandled = false;
    }
    // The real element plays again: the system interruption is over.
    if (_systemPaused && playing) {
      _systemPaused = false;
      _systemPausedAt = Duration.zero;
      _backgroundResumeAllowed = true;
    }

    final position = _seconds(data['position']);
    final duration = _seconds(data['duration']);

    if (PlaybackPolicy.shouldUnmute(
      playing: playing,
      ended: ended,
      muted: data['muted'] == true,
      adShowing: adShowing,
      sinceLastAttempt: DateTime.now().difference(_lastUnmuteAttempt),
    )) {
      _lastUnmuteAttempt = DateTime.now();
      unawaited(video.unmute());
    }

    _checkStuckPip(data['pipStuck'] == true);

    final wasPlaying = _player.isPlaying;
    var current = _player.video;
    if (current == null && playing && !ended) current = _trackFromUrl();
    if (current != null) {
      _playerN.sync(isPlaying: playing && !ended, position: position, duration: duration);
      _updateNowPlaying(position: position, duration: duration, playing: playing && !ended);
      final stats = _ref.read(statsRepositoryProvider);
      if (playing && !ended) {
        stats
          ..recordTick(current.platform, position)
          ..saveProgress(current.id, position);
      } else {
        stats.resetTrack();
      }
    }

    if (PlaybackPolicy.shouldHoldWebView(
      wasPlaying: wasPlaying,
      playing: playing,
      ended: ended,
      backgrounded: _backgrounded,
      backgroundAudio: _settings.backgroundAudio,
      isMusic: _isMusic,
      userPaused: _userPaused,
      systemPaused: _systemPaused,
      handoffPending: _handoffPending,
    )) {
      _holdWebViewWhilePaused();
    }

    final keepAlive = _ref.read(keepAliveAudioProvider);
    if (_isMusic) {
      // Music: no PiP (YTM disables it), audio-only playback is kept alive by
      // the silent loop, and a system-forced background pause is resumed.
      if (playing && !ended) {
        if (_settings.backgroundAudio) unawaited(keepAlive.start());
        _userPaused = false;
      } else if (ended) {
        // Keep the loop through the song change in the background, or iOS
        // suspends the page before the next song starts.
        if (!_backgrounded || !_settings.backgroundAudio) unawaited(keepAlive.stop());
        _onEnded(current);
      } else if (!_backgrounded) {
        unawaited(keepAlive.stop());
      } else if (_backgroundResumeAllowed && data['pip'] != true) {
        unawaited(video.play());
      }
    } else if (ended) {
      _onEnded(current);
    }
  }

  Duration _seconds(Object? value) {
    final s = value is num ? value.toDouble() : 0.0;
    // Live streams can report Infinity/NaN.
    return s.isFinite ? Duration(milliseconds: (s * 1000).round()) : Duration.zero;
  }

  void _checkStuckPip(bool pipStuck) {
    final bg = _backgrounded || _inactive;
    if (pipStuck && !bg) {
      _pipStuckSince ??= DateTime.now();
    } else {
      _pipStuckSince = null;
    }
    final since = _pipStuckSince;
    if (PlaybackPolicy.shouldForceInline(
      pipStuck: pipStuck,
      backgrounded: bg,
      stuckFor: since == null ? Duration.zero : DateTime.now().difference(since),
      sinceLastForce: DateTime.now().difference(_lastInlineForce),
    )) {
      _lastInlineForce = DateTime.now();
      unawaited(video.forceInline());
    }
  }

  void _updateNowPlaying({required Duration position, required Duration duration, required bool playing}) {
    if (!FeatureFlags.nativeLockScreen) return;
    final changed = playing != _lastNowPlayingPlaying;
    if (!changed && (position.inMilliseconds - _lastNowPlayingMs).abs() < 1000) return;
    _lastNowPlayingMs = position.inMilliseconds;
    _lastNowPlayingPlaying = playing;
    unawaited(
      _ref.read(nowPlayingProvider).setProgress(
            position: _systemPaused ? _systemPausedAt : position,
            duration: duration,
            isPlaying: playing && !_systemPaused,
          ),
    );
  }

  // =====================================================================
  // Tracking
  // =====================================================================

  void _resetForNewVideo(String url) {
    _lastUnmuteAttempt = _epoch;
    _userPaused = false;
    _systemPaused = false;
    _systemPausedAt = Duration.zero;
    _lastPlayStart = DateTime.now();
    _lastNowPlayingMs = 0;
    _isMusic = UrlUtils.isMusic(url);
    _ref.read(statsRepositoryProvider).resetTrack();
  }

  void _startTracking(Video v) {
    _playerN.track(v, videoTab: _browser.hasVideoTab);
    _startStatePoll();
    _onTrackChanged(v);
  }

  /// Side effects of a new video: history, analytics, Spotlight, Now Playing.
  void _onTrackChanged(Video v) {
    if (_settings.historyEnabled) unawaited(_ref.read(historyRepositoryProvider).record(v));
    _ref.read(analyticsProvider).event('video_play', {
      'platform': v.platform.isEmpty ? 'unknown' : v.platform,
      'source': _browser.hasVideoTab ? 'video_tab' : 'player',
    });
    _indexInSpotlight(v);
    unawaited(_ref.read(nowPlayingProvider).setTrack(title: v.title, artist: v.platform, artworkUrl: v.thumbnailUrl));
  }

  void _indexInSpotlight(Video v) {
    if (v.hasPlaceholderTitle) return;
    unawaited(
      _ref.read(spotlightProvider).index(
            title: v.title,
            subtitle: v.platform.isEmpty ? 'MrPlay' : v.platform,
            url: v.url,
          ),
    );
  }

  /// Tracks the current page as a placeholder video when the title script
  /// never reported in, so the mini player and stats still appear.
  Video? _trackFromUrl() {
    final existing = _player.video;
    if (existing != null) return existing;
    final url = _browser.videoTabUrl ?? _browser.browseUrl ?? '';
    final v = Video.fromUrl(url);
    if (v == null) return null;
    _resetForNewVideo(url);
    _startTracking(v);
    return v;
  }

  /// The video tab navigated to another video (related video, autoplay):
  /// track it right away so the mini player stops showing the old one.
  void _trackPlaceholder(String url) {
    if (_player.video?.url == url) return;
    final v = Video.fromUrl(url);
    if (v == null) return;
    _resetForNewVideo(url);
    if (_player.video == null) {
      _startTracking(v);
    } else {
      _playerN.updateMetadata(v);
      _onTrackChanged(v);
    }
  }

  void _startStatePoll() {
    // The page's own events get throttled while Flutter UI covers the
    // webview; polling keeps position/duration fresh.
    _statePoll?.cancel();
    _statePoll = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(_pollState()));
  }

  void _stopStatePoll() {
    _statePoll?.cancel();
    _statePoll = null;
  }

  Future<void> _pollState() async {
    if (!_player.hasVideo) return _stopStatePoll();
    final s = await video.state();
    if (s != null) _onVideoState(s);
  }

  // =====================================================================
  // Queue
  // =====================================================================

  /// Advances the queue when a video ends — in the foreground and the
  /// background (the keep-alive keeps `ended` reaching Dart).
  void _onEnded(Video? current) {
    final stats = _ref.read(statsRepositoryProvider);
    if (current != null) stats.clearProgress(current.id);
    unawaited(stats.flush());
    unawaited(_advanceQueue());
  }

  Future<void> _advanceQueue() async {
    if (_endedHandled) return;
    _endedHandled = true;
    final next = await _ref.read(queueRepositoryProvider).takeNext();
    if (next == null) {
      // No MrPlay queue: the page's own autoplay goes on. Keep the webview
      // alive in the background so it can.
      if (_backgrounded && _settings.backgroundAudio) {
        unawaited(_ref.read(keepAliveAudioProvider).start());
      }
      return;
    }
    await video.exitPip();
    _lastUnmuteAttempt = _epoch;
    if (UrlUtils.routesToVideoTab(next.url) && _browser.hasVideoTab) {
      if (_browser.videoTabUrl == next.url) {
        // YouTube's own autoplay already navigated there: don't reload.
        unawaited(video.resumeOrStart());
        unawaited(video.unmute());
      } else {
        _openVideoTab(next.url);
      }
    } else {
      if (_browser.hasVideoTab) closePlayer();
      loadUrl(next.url);
    }
    if (_backgrounded && _settings.backgroundAudio) {
      _handoffPending = true;
      unawaited(_reengageBackgroundKeepAlive());
    }
  }

  /// After a background queue handoff: wait for the next video, force-start
  /// it if its autoplay stalled, then re-apply the keep-alive.
  Future<void> _reengageBackgroundKeepAlive() async {
    for (var i = 0; i < 15 && !_player.isPlaying; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (!_backgrounded || !_settings.backgroundAudio || _userPaused || _systemPaused) return;
    if (!_player.isPlaying) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await video.resumeOrStart();
      await video.unmute();
    }
    await _engageBackgroundKeepAlive();
    if (!_player.isPlaying) _holdWebViewWhilePaused();
  }

  // =====================================================================
  // Background audio
  // =====================================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // Also Control Center pulled over the app: not a background.
        _inactive = true;
      case AppLifecycleState.paused:
        _pausedAt ??= DateTime.now();
        _enterBackground();
      case AppLifecycleState.resumed:
        _onResumed();
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _enterBackground() {
    if (_backgrounded) return;
    _backgrounded = true;
    final playing = _player.isPlaying;
    _backgroundResumeAllowed = _settings.backgroundAudio && playing && !_userPaused;
    unawaited(_reassertAudioSession());
    if (playing) {
      if (_settings.backgroundAudio) {
        unawaited(_engageBackgroundKeepAlive());
      } else {
        // Background audio off: behave like a normal browser and stop.
        unawaited(_ref.read(keepAliveAudioProvider).stop());
        _lastKnownPlaying = _epoch;
        _playerN.setPlaying(false);
        unawaited(video.pause());
      }
    } else if (_settings.backgroundAudio && _userPaused && !_systemPaused) {
      // Paused from Control Center: keep the webview reachable for play.
      unawaited(_ref.read(keepAliveAudioProvider).start());
    }
    unawaited(_ref.read(statsRepositoryProvider).flush());
  }

  void _onResumed() {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    final kickStuckVideo = _handoffPending && !_systemPaused && !_userPaused && _settings.backgroundAudio;
    final wasBackgrounded = _backgrounded;
    _backgrounded = false;
    _inactive = false;
    if (!wasBackgrounded) return;

    if (_userPaused) unawaited(video.softPauseToReal());
    _userPaused = false;
    _stoppedUnexpectedly = false;
    _handoffPending = false;
    _stopPausedKeepAlive();
    // In the foreground the visible player holds the session; only Music
    // keeps the silent loop while it plays.
    if (!_isMusic || (!_player.isPlaying && !_systemPaused)) {
      unawaited(_ref.read(keepAliveAudioProvider).stop());
    }

    // Long-idle session: back to the hub (never while something plays).
    if (pausedAt != null &&
        !_player.isPlaying &&
        DateTime.now().difference(pausedAt) >= FeatureFlags.sessionTimeout) {
      goHub();
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 300), _restoreInline);
    Future<void>.delayed(const Duration(seconds: 4), _recoverStuckVideo);
    if (kickStuckVideo) {
      Future<void>.delayed(const Duration(milliseconds: 1200), _ensureResumedVideoPlays);
    }
  }

  Future<void> _engageBackgroundKeepAlive({bool userPlay = false}) async {
    if (_isMusic) {
      await _ref.read(keepAliveAudioProvider).start();
      if (userPlay) await video.play();
      return;
    }
    // Phantom PiP, retried once: the first background of a session has a
    // cold PiP pipeline that can lose the race against suspension.
    var result = await video.enterPhantomPip(userPlay: userPlay);
    if (result.ok) return;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!userPlay && _userPaused) return;
    result = await video.enterPhantomPip(userPlay: userPlay);
    if (!result.ok) log('phantom PiP failed: ${result.reason}');
  }

  /// Lock-screen play while backgrounded: re-establish the audio session and
  /// the silent loop first — without live audio the WebContent process is
  /// already suspended and JS would never run.
  Future<void> _resumeFromBackground() async {
    await _reassertAudioSession();
    await _ref.read(keepAliveAudioProvider).start();
    await _engageBackgroundKeepAlive(userPlay: true);
  }

  void _holdWebViewWhilePaused() {
    if (!_backgrounded || !_settings.backgroundAudio) return;
    _stoppedUnexpectedly = true;
    unawaited(_reassertAudioSession());
    unawaited(_ref.read(keepAliveAudioProvider).start());
    _startPausedKeepAlive();
  }

  /// While paused in the background, periodically re-asserts phantom PiP so
  /// the WebContent process stays reachable for a lock-screen play.
  void _startPausedKeepAlive() {
    _pausedKeepAlive?.cancel();
    _pausedKeepAlive = Timer.periodic(const Duration(seconds: 4), (_) {
      final stillNeeded = _backgrounded &&
          _settings.backgroundAudio &&
          !_player.isPlaying &&
          (_userPaused || _stoppedUnexpectedly);
      if (!stillNeeded) return _stopPausedKeepAlive();
      unawaited(video.reassertPhantomPip());
    });
  }

  void _stopPausedKeepAlive() {
    _pausedKeepAlive?.cancel();
    _pausedKeepAlive = null;
  }

  Future<void> _reassertAudioSession() async {
    try {
      await (await AudioSession.instance).setActive(true);
    } on Exception catch (e) {
      log('audio session reassert failed: $e');
    }
  }

  /// Restores a phantom-PiP'd video inline after resume; reloads only as a
  /// last resort (an eager reload showed a black player + loader).
  Future<void> _restoreInline() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(milliseconds: 500));
      final r = await video.restoreInline();
      if (r.ok) return;
      log('inline restore attempt failed: ${r.reason}');
    }
    await _activeController?.reload();
    Future<void>.delayed(const Duration(milliseconds: 1500), () async {
      await video.resumeOrStart();
      await video.unmute();
    });
  }

  /// A video left on its loader after the background: nudge it, then reload
  /// and seek back if it is still stuck. A healthy video is never touched.
  Future<void> _recoverStuckVideo({int attempt = 0}) async {
    if (_backgrounded || !_player.hasVideo) return;
    final s = await video.state();
    if (s == null || s['buffering'] != true) return;
    final pos = _seconds(s['position']);
    log('video stuck loading after resume (attempt $attempt)');
    if (attempt == 0) {
      await video.nudge(play: _player.isPlaying);
      Future<void>.delayed(const Duration(seconds: 5), () => _recoverStuckVideo(attempt: 1));
      return;
    }
    final wasPlaying = _player.isPlaying;
    await _activeController?.reload();
    Future<void>.delayed(const Duration(seconds: 3), () async {
      if (_backgrounded) return;
      await video.seek(pos);
      if (wasPlaying) {
        await video.resumeOrStart();
      } else {
        await video.pause();
      }
    });
  }

  /// A background handoff left the next video on its loader: start it.
  Future<void> _ensureResumedVideoPlays({int attempt = 0}) async {
    if (_userPaused || _systemPaused || !_player.hasVideo || _player.isPlaying) return;
    await video.resumeOrStart();
    await video.unmute();
    if (attempt < 2) {
      Future<void>.delayed(const Duration(milliseconds: 800), () => _ensureResumedVideoPlays(attempt: attempt + 1));
    }
  }

  // =====================================================================
  // Interruptions & native remote commands
  // =====================================================================

  Future<void> _subscribeToInterruptions() async {
    try {
      final session = await AudioSession.instance;
      _interruptions = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          if (_player.isPlaying) unawaited(_onInterruptionBegan());
        } else if (_systemPaused) {
          unawaited(_onInterruptionEnded());
        }
      });
    } on Exception catch (e) {
      log('interruption subscribe failed: $e');
    }
  }

  /// A real interruption pauses the element itself; transient session
  /// toggling (ad SDK, WebKit first-play handoff) doesn't, so verify first.
  Future<void> _onInterruptionBegan() async {
    if (!_backgrounded) {
      if (DateTime.now().difference(_lastPlayStart) < PlaybackPolicy.interruptionGrace) return;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _pollState();
      if (_player.isPlaying) return;
    }
    _systemPause();
  }

  void _systemPause() {
    _systemPaused = true;
    _backgroundResumeAllowed = false;
    _lastKnownPlaying = _epoch;
    _systemPausedAt = _player.position;
    if (_isMusic) unawaited(_ref.read(keepAliveAudioProvider).stop());
    _playerN.setPlaying(false);
    unawaited(video.pause());
    unawaited(
      _ref.read(nowPlayingProvider).setProgress(
            position: _systemPausedAt,
            duration: _player.duration,
            isPlaying: false,
          ),
    );
  }

  Future<void> _onInterruptionEnded() async {
    _systemPaused = false;
    _systemPausedAt = Duration.zero;
    await _reassertAudioSession();
    if (!_backgrounded || !_settings.backgroundAudio) return;
    if (_player.isPlaying) {
      await _engageBackgroundKeepAlive();
    } else if (!_userPaused) {
      // Keep the webview alive so a lock-screen play can reach it.
      await _ref.read(keepAliveAudioProvider).start();
    }
  }

  /// Native commands: the headphone/Bluetooth-disconnect pause, plus the
  /// full lock-screen set when [FeatureFlags.nativeLockScreen] is on.
  void _onNativeCommand(String command, Duration? position) {
    log('native command=$command bg=$_backgrounded', tag: 'lock');
    if (!_player.hasVideo) return;
    switch (command) {
      case 'play':
        resume();
      case 'pause':
        pause();
      case 'toggle':
        togglePlay();
      case 'skipForward':
        _remoteSeek(_player.position + const Duration(seconds: 15));
      case 'skipBackward':
        _remoteSeek(_player.position - const Duration(seconds: 15));
      case 'seek':
        if (position != null) _remoteSeek(position);
    }
  }

  /// iOS pauses the element during a lock-screen scrub and never sends play
  /// afterwards; resume once the drag settles if it was playing at the start.
  void _remoteSeek(Duration target) {
    final now = DateTime.now();
    if (now.difference(_lastSeekDragTick) >= const Duration(milliseconds: 700)) {
      _wasPlayingAtSeek = _player.isPlaying || now.difference(_lastKnownPlaying) < const Duration(seconds: 5);
    }
    _lastSeekDragTick = now;
    seekTo(target);
    _remoteSeekResume?.cancel();
    _remoteSeekResume = Timer(const Duration(milliseconds: 350), () {
      if (!_wasPlayingAtSeek && !_player.isPlaying) return;
      if (_backgrounded && !_settings.backgroundAudio) return;
      resume();
    });
  }

  // =====================================================================
  // Settings
  // =====================================================================

  void _onSettingsChanged(AppSettings next) {
    final prev = _settings;
    _settings = next;
    final controllers = [_browse, _video].whereType<InAppWebViewController>();
    if (prev.adBlock != next.adBlock) {
      for (final c in controllers) {
        unawaited(scripts.applyAdBlock(c, enabled: next.adBlock));
      }
    }
    if (prev.blockPopups != next.blockPopups) {
      for (final c in controllers) {
        unawaited(scripts.applyPopupBlock(c, enabled: next.blockPopups));
      }
    }
  }
}
