import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:audio_session/audio_session.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/youtube_js.dart';
import '../../core/constants/content_blocker_js.dart';
import '../../core/constants/media_observer_js.dart';
import '../../models/video.dart';
import '../../providers/player_provider.dart';
import '../../services/media_controls_service.dart';
import '../../services/background_audio_keep_alive.dart';
import '../../services/playback_stats_service.dart';
import '../../services/data_export_service.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/watch_later_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/models/favorite_video.dart';
import '../../data/models/queue_item.dart';
import '../../data/models/playlist.dart';
import '../../data/models/playlist_item.dart';
import '../../presentation/pages/settings_page.dart';
import '../../presentation/pages/favorites_page.dart';
import '../../widgets/sleep_timer_sheet.dart';
import 'error_widget.dart';

class PersistentWebView extends ConsumerStatefulWidget {
  const PersistentWebView({super.key});

  @override
  ConsumerState<PersistentWebView> createState() => PersistentWebViewState();
}

class PersistentWebViewState extends ConsumerState<PersistentWebView>
    with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  InAppWebViewController? _videoWebViewController;
  String? _videoTabUrl;
  String? _pendingVideoUrl;
  double _tabSwipeOffset = 0;
  bool _waitingToGoBack = false;
  bool _videoTabIntro = false;
  bool _unmuteDone = false;
  bool isReady = false;

  /// True while the hub page is the visible layer (webview not ready / not
  /// covering it). The app's Stack watches this so the floating banner hides
  /// while the hub shows its own ad slot.
  static final ValueNotifier<bool> hubVisible = ValueNotifier(true);
  bool _isLoading = false;
  bool _adBlockEnabled = false;
  bool _backgroundAudioEnabled = false;
  String? _pendingUrl;
  String? _currentUrl;
  /// Last URL loaded in the browse webview, saved before blanking so we can
  /// restore it when the video tab collapses back to mini.
  String? _lastBrowseUrl;
  String? _loadError;
  Timer? _loadingTimer;
  Timer? _nowPlayingThrottle;
  bool _endedHandled = false;
  bool _appIsBackgrounded = false;
  // Whether a system-forced pause (iOS suspends the webview's media when the
  // app backgrounds / the screen locks) may be auto-resumed to keep audio
  // playing. User-initiated pauses clear this so they are not fought. Used for
  // YouTube Music (audio-only), whose playback is kept alive by the silent loop
  // rather than phantom-PiP.
  bool _backgroundResumeAllowed = false;
  bool _userPausedInBackground = false;
  // Latched true when the system pauses us (another app / a call takes the
  // audio session). While latched, the state poll / JS events must not re-mark
  // Now Playing as "playing", so Control Center shows the true paused state and
  // the elapsed time stays put. Cleared on explicit user resume or a new video.
  bool _systemPaused = false;
  // Elapsed seconds frozen at the moment of a system pause (call / other app
  // seizing the audio session). Used to hold the Now Playing elapsed time
  // steady so iOS doesn't keep counting up while the video is actually paused.
  double _systemPausedElapsed = 0;
  // True while the tracked video is a YouTube Music (music.youtube.com) page.
  bool _isMusic = false;
  int _lastNowPlayingMs = 0;
  bool _adActive = false;
  bool _wasPlayingBeforeAd = false;
  bool _browsePreloaded = false;
  Timer? _statePoll;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  /// JS that resolves the actively-playing `<video>` (falling back to the
  /// first one), so controls target the real playback element rather than a
  /// stale/ad/preview video that `document.querySelector('video')` may hit.
  static const String _activeVideoJs = '''
    (function() {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        if (!videos[i].paused && !videos[i].ended) return videos[i];
      }
      return videos.length > 0 ? videos[0] : null;
    })()
  ''';

  static bool _isAdDomain(String host) {
    final h = host.toLowerCase();
    const adDomains = [
      'doubleclick.net',
      'googlesyndication.com',
      'googleadservices.com',
      'google-analytics.com',
      'adservice.google.com',
      'pagead2.googlesyndication.com',
      'tpc.googlesyndication.com',
    ];
    for (final d in adDomains) {
      if (h == d || h.endsWith('.$d')) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MediaControlsService.instance.setRemoteCommandHandler(_onRemoteCommand);
    _subscribeToAudioInterruptions();
    _loadAdBlockSetting();
    _loadBackgroundAudioSetting();
  }

  /// Reads the "Block ads & trackers" preference from Settings. Off by default
  /// so the app presents as a plain browser to App Review; the user can opt in
  /// from Settings at any time.
  Future<void> _loadAdBlockSetting() async {
    final enabled = await SettingsRepository.getAdBlockEnabled();
    if (mounted && enabled != _adBlockEnabled) {
      setState(() => _adBlockEnabled = enabled);
    }
  }

  /// Reads the "Background audio" preference. Off by default: the app stops
  /// audio when backgrounded (standard browser behavior). When enabled, the
  /// phantom-PiP keep-alive keeps playback alive in the background.
  Future<void> _loadBackgroundAudioSetting() async {
    final enabled =
        await SettingsRepository.getBackgroundAudioEnabled();
    if (mounted && enabled != _backgroundAudioEnabled) {
      setState(() => _backgroundAudioEnabled = enabled);
    }
  }

  /// Blanks the browse webview to free ~150MB of WebContent process memory.
  /// The current URL is saved in [_lastBrowseUrl] so it can be restored when
  /// the video tab collapses.
  void _blankBrowseWebview() {
    _lastBrowseUrl = _currentUrl;
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
    _currentUrl = null;
  }

  /// Restores the browse webview after it was blanked. Uses the saved
  /// [_lastBrowseUrl] or falls back to YouTube home.
  void _restoreBrowseWebview() {
    final url = _lastBrowseUrl;
    if (url != null && url.isNotEmpty && _webViewController != null) {
      _webViewController!.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
      _currentUrl = url;
    } else if (_webViewController != null) {
      _webViewController!.loadUrl(
        urlRequest: URLRequest(url: WebUri('https://m.youtube.com')),
      );
    }
  }

  /// Another app (TikTok, Spotify, a call...) has taken the audio session -
  /// iOS pauses our playback and silences the phantom-PiP keep-alive. Update
  /// the player state and Now Playing so Control Center doesn't keep showing
  /// "playing" while the video is actually paused. When the interruption ends
  /// the webview stays paused; the user resumes explicitly.
  Future<void> _subscribeToAudioInterruptions() async {
    try {
      final session = await AudioSession.instance;
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (!event.begin) return;
        if (!mounted) return;
        if (_adActive) return;
        if (ref.read(playerProvider).isPlaying) {
          _systemPause();
        }
      });
    } catch (e) {
      debugPrint('[MrPlay] audio interruption subscribe failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadingTimer?.cancel();
    _nowPlayingThrottle?.cancel();
    _statePoll?.cancel();
    _interruptionSub?.cancel();
    PlaybackStatsService.instance.flush();
    BackgroundAudioKeepAlive.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _appIsBackgrounded = true;
    } else if (state == AppLifecycleState.paused) {
      _enterBackground();
    } else if (state == AppLifecycleState.resumed) {
      _appIsBackgrounded = false;
      _userPausedInBackground = false;
      // Stop the keep-alive when the app is back in the foreground and the
      // video is not playing (the silent loop is no longer needed).
      if (!ref.read(playerProvider).isPlaying && !_systemPaused) {
        BackgroundAudioKeepAlive.instance.stop();
      }
      // The video was phantom-PiP'd on background to keep audio alive. Restore
      // it inline after a short delay so WebKit can finish its own reattachment
      // first; the restore is event-driven (webkitpresentationmodechanged)
      // with a page reload as a last resort.
      Future.delayed(const Duration(milliseconds: 300), _restoreVideoInline);
      // Browse was blanked on background to free memory. Restore it when the
      // user is going to see it (no video tab, or the video tab is minimized).
      // Keep it blank while the expanded video tab covers it.
      final vidTabExpanded = _videoTabUrl != null &&
          ref.read(playerProvider).isVideoTab &&
          !ref.read(playerProvider).isMinimized;
      if (!vidTabExpanded &&
          _pendingUrl == null &&
          _lastBrowseUrl != null &&
          _currentUrl == null) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _restoreBrowseWebview();
        });
      }
    }
  }

  void _enterBackground() {
    _appIsBackgrounded = true;
    _backgroundResumeAllowed = _backgroundAudioEnabled &&
        ref.read(playerProvider).isPlaying &&
        !_userPausedInBackground;
    _reassertAudioSession();
    if (ref.read(playerProvider).isPlaying) {
      if (_backgroundAudioEnabled) {
        if (_isMusic) {
          BackgroundAudioKeepAlive.instance.start();
        } else {
          _enterPhantomPiP();
        }
      } else {
        BackgroundAudioKeepAlive.instance.stop();
        ref.read(playerProvider.notifier).pause();
        MediaControlsService.instance.setPlaying(false);
        controlVideo('pause');
      }
    } else if (_backgroundAudioEnabled &&
        _userPausedInBackground &&
        !_systemPaused) {
      // User paused from Control Center while backgrounded. Keep the silent
      // loop alive so iOS doesn't suspend the WebView — without it, Control
      // Center's play button can't reach the webview.
      BackgroundAudioKeepAlive.instance.start();
    }
    // Memory cleanup: blank the browse webview whenever it is hidden (video
    // tab is active) and blank both webviews when backgrounded without audio.
    // WKWebView runs out-of-process, so this frees ~150-300 MB of WebContent
    // memory — the main cause of device heating.
    if (!ref.read(playerProvider).isPlaying) {
      // No playback — safe to blank everything for maximum memory recovery.
      _blankBrowseWebview();
      _videoWebViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')),
      );
    } else if (_videoTabUrl != null) {
      // Audio playing but browse is hidden behind the video tab.
      _blankBrowseWebview();
    }
  }

  Future<void> _reassertAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      debugPrint('[MrPlay] audio session reassert failed: $e');
    }
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
    _registerVideoHandlers(controller);
    if (_pendingUrl != null) {
      controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(_pendingUrl!)),
      );
      _pendingUrl = null;
    }
  }

  void _onVideoWebViewCreated(InAppWebViewController controller) {
    _videoWebViewController = controller;
    _registerVideoHandlers(controller);
    // initialUrlRequest already started the load; only issue a second
    // navigation when the stashed URL differs (a video replaced mid-creation).
    if (_pendingVideoUrl != null && _pendingVideoUrl != _videoTabUrl) {
      controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(_pendingVideoUrl!)),
      );
      _pendingVideoUrl = null;
    }
  }

  /// Registers the JS<->Dart bridges used to feed the player/controls. Shared
  /// between the browse webview and the video tab. Player actions always
  /// target the most recently created controller, so the video tab wins when
  /// it is present.
  void _registerVideoHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'playerInfo',
      callback: (args) {
        if (args.isNotEmpty && args.first is Map) {
          _onPlayerInfo(args.first as Map<String, dynamic>);
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'videoState',
      callback: (args) {
        if (args.isNotEmpty && args.first is Map) {
          _onVideoState(args.first as Map<String, dynamic>);
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'playerControl',
      callback: (args) {
        if (args.isEmpty || args.first is! Map) return;
        final action =
            (args.first as Map<String, dynamic>)['action'] as String?;
        switch (action) {
          case 'toggleCaptions':
            controlVideo('toggleCaptions');
            break;
          case 'pip':
            togglePictureInPicture();
            break;
          case 'fullscreen':
            controlVideo('fullscreen');
            break;
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'videoTabSwipe',
      callback: (args) {
        _minimizeVideoTab();
      },
    );
  }

  InAppWebViewController? get _activeController =>
      _videoWebViewController ?? _webViewController;

  /// Only m.youtube.com watch pages get routed into the dedicated video tab.
  /// YouTube Music keeps playing inline in its own tab by design, so
  /// music.youtube.com watch URLs are excluded.
  bool _routesToVideoTab(String url) {
    if (!url.contains('/watch')) return false;
    if (url.contains('music.youtube.com')) return false;
    return url.contains('youtube.com');
  }

  bool _isMusicUrl(String? url) =>
      url != null && url.contains('music.youtube.com');

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    _currentUrl = url?.toString();
    if (mounted) setState(() => _isLoading = true);
    if (_loadError != null && mounted) setState(() => _loadError = null);
    _loadingTimer?.cancel();
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _onLoadStop(
      InAppWebViewController controller, WebUri? url) async {
    _loadingTimer?.cancel();
    if (mounted) setState(() => _isLoading = false);
    final urlStr = url.toString();
    if (_routesToVideoTab(urlStr)) {
      if (_videoTabUrl != null && _videoTabUrl == urlStr) {
        _handleWatchPage(controller, urlStr);
        return;
      }
      _openVideoTab(urlStr);
      return;
    }
    _handleWatchPage(controller, urlStr);
  }

  /// YouTube mobile is a single-page app: tapping a video navigates to /watch
  /// via the history API, so neither onLoadStart nor onLoadStop fires. iOS
  /// reports those URL changes through onUpdateVisitedHistory (KVO on
  /// WKWebView.url). The browse webview re-routes /watch pages into the
  /// dedicated video tab and steps back so the normal navigation surface is
  /// always the search/home feed.
  void _onBrowseVisitedHistory(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  ) {
    final urlStr = url?.toString();
    if (urlStr == null) return;
    _currentUrl = urlStr;
    if (_routesToVideoTab(urlStr)) {
      _openVideoTab(urlStr);
      // YouTube uses pushState, so stepping back returns to the feed while the
      // new tab keeps the watch page alive. Guard against re-entry so a queued
      // back call doesn't bounce us forward again.
      if (_waitingToGoBack) return;
      _waitingToGoBack = true;
      Future.delayed(const Duration(milliseconds: 80), () {
        _waitingToGoBack = false;
        try {
          controller.goBack();
        } catch (e) {
          debugPrint('[MrPlay] goBack failed: $e');
        }
      });
      return;
    }
    _handleWatchPage(controller, urlStr);
  }

  /// The video tab also tracks its own watch navigations (related video,
  /// autoplay queue). The SPA has already navigated by the time this fires, so
  /// we only update the tracked URL + re-run watch tasks — never reload.
  void _onVideoVisitedHistory(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  ) {
    final urlStr = url?.toString();
    if (urlStr == null) return;
    if (urlStr.contains('youtube.com') && urlStr.contains('/watch')) {
      if (urlStr != _videoTabUrl) {
        _videoTabUrl = urlStr;
        _endedHandled = false;
      }
      _handleWatchPage(controller, urlStr);
    }
  }

  void _onVideoLoadStart(InAppWebViewController controller, WebUri? url) {
    final urlStr = url?.toString();
    if (urlStr == null) return;
    if (urlStr.contains('youtube.com') && urlStr.contains('/watch')) {
      if (urlStr != _videoTabUrl) _openVideoTab(urlStr);
    }
  }

  /// Runs the watch-page tasks (title extraction for the mini player).
  /// Safe to call repeatedly for the same page: playerInfo is deduped by
  /// video id.
  void _handleWatchPage(InAppWebViewController controller, String urlStr) {
    if (urlStr.contains('youtube.com')) {
      if (urlStr.contains('/watch')) {
        Future.delayed(const Duration(milliseconds: 1500), () async {
          if (!mounted) return;
          await controller.evaluateJavascript(source: '''
            (function() {
              var titleEl = document.querySelector('h1.title, .slim-video-information-title, .ytp-title, #title h1');
              var videoId = window.location.search.match(/[?&]v=([^&]+)/);
              var title = titleEl ? titleEl.textContent.trim().substring(0, 200) : '';
              if (title && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('playerInfo', {
                  id: videoId ? videoId[1] : '',
                  title: title,
                  thumbnailUrl: videoId ? 'https://i.ytimg.com/vi/' + videoId[1] + '/hqdefault.jpg' : '',
                  videoUrl: window.location.href,
                  platform: 'YouTube'
                });
              }
            })();
          ''');
        });
      }
    }
  }

  void _onPlayerInfo(Map<String, dynamic> data) {
    try {
      final title = data['title'] as String? ?? '';
      if (title.isNotEmpty) {
        final video = Video(
          id: data['id'] ?? '',
          title: title,
          thumbnailUrl: data['thumbnailUrl'] ?? '',
          videoUrl: data['videoUrl'] ?? '',
          platform: data['platform'] ?? 'YouTube',
        );
        final currentId = ref.read(playerProvider).currentVideo?.id;
        if (currentId != video.id) {
          _endedHandled = false;
          _unmuteDone = false;
          _userPausedInBackground = false;
          _systemPaused = false;
          _systemPausedElapsed = 0;
          _isMusic = _isMusicUrl(video.videoUrl);
          if (_videoTabUrl != null) {
            ref.read(playerProvider.notifier).openVideoTab(video);
          } else {
            ref.read(playerProvider.notifier).play(video);
          }
          MediaControlsService.instance.updateNowPlaying(
            title: video.title,
            artist: video.platform.isEmpty ? 'YouTube' : video.platform,
            position: Duration.zero,
            duration: Duration.zero,
            isPlaying: true,
            artworkUrl: video.thumbnailUrl,
          );
          _lastNowPlayingMs = 0;
        } else {
          // Same video already tracked (fallback placeholder created it):
          // upgrade its metadata to the real title/thumbnail.
          final current = ref.read(playerProvider).currentVideo;
          if (current != null &&
              (current.title == 'YouTube video' ||
                  current.title == 'Playing video')) {
            ref.read(playerProvider.notifier).updateMetadata(video);
          }
        }
      }
    } catch (e) {
      debugPrint('[MrPlay] _onPlayerInfo error: $e');
    }
  }

  void _onVideoState(Map<String, dynamic> data) {
    try {
      var playing = data['playing'] == true;
      final ended = data['ended'] == true;
      final pip = data['pip'] == true;
      // While the system has latched us as paused (another app / a call took
      // the audio session), ignore any "playing" report from the poll / JS so
      // Now Playing can't be flipped back to "playing" out of sync with the
      // actual (paused) video.
      if (_systemPaused && playing) {
        playing = false;
      }
      // Live streams can report non-finite position/duration - clamp to 0 so
      // Duration(milliseconds:) never receives Infinity/NaN (which throws).
      final posSec = (data['position'] as num?)?.toDouble() ?? 0;
      final durSec = (data['duration'] as num?)?.toDouble() ?? 0;
      final positionMs = posSec.isFinite ? posSec * 1000 : 0.0;
      final durationMs = durSec.isFinite ? durSec * 1000 : 0.0;
      // YouTube starts some videos muted (or the user previously muted); once
      // the video is actually playing, force-unmute it so audio is audible.
      // `_unmuteDone` is set to true only once unmuting is *confirmed* (the
      // active element is audible), otherwise the next report retries. This
      // fixes videos that open muted because the first unmute attempt ran
      // before the element was ready and was never retried.
      if (playing && !ended && !_unmuteDone) {
        _unmuteVideo().then((audible) {
          if (mounted && audible) _unmuteDone = true;
        });
      }
      var video = ref.read(playerProvider).currentVideo;
      // Fallback: if the video is actually playing but the `playerInfo` JS
      // (title extraction) never reported in, build the Video from the current
      // URL so the mini player / stats / media controls still appear.
      if (video == null && playing && !ended) {
        video = _trackVideoFromUrl();
      }
      if (video != null) {
        ref.read(playerProvider.notifier).syncState(
              isPlaying: playing,
              position: Duration(milliseconds: positionMs.round()),
              duration: Duration(milliseconds: durationMs.round()),
              ended: ended,
            );
        _updateNowPlayingThrottled(
          positionMs: positionMs.round(),
          durationMs: durationMs.round(),
          playing: playing,
        );
        if (playing && !ended) {
          PlaybackStatsService.instance.saveProgress(
            video.id,
            Duration(milliseconds: positionMs.round()),
          );
        }
      }
      if (_isMusic) {
        // YouTube Music: keep the silent loop alive while playing and
        // auto-resume a system-forced background pause (PiP can't take over
        // because YTM disables it, so we rely on native audio-only playback).
        if (playing && !ended) {
          if (_backgroundAudioEnabled) {
            BackgroundAudioKeepAlive.instance.start();
          }
          _userPausedInBackground = false;
        } else if (!_appIsBackgrounded) {
          BackgroundAudioKeepAlive.instance.stop();
          if (ended) {
            PlaybackStatsService.instance.flush();
            final id = video?.id ?? '';
            if (id.isNotEmpty) PlaybackStatsService.instance.clearProgress(id);
            _handleEnded();
          }
        } else if (!ended && _backgroundResumeAllowed && !pip) {
          controlVideo('play');
        }
      } else {
        if (!playing && !_appIsBackgrounded && ended) {
          PlaybackStatsService.instance.flush();
          final id = video?.id ?? '';
          if (id.isNotEmpty) PlaybackStatsService.instance.clearProgress(id);
          _handleEnded();
        }
      }
    } catch (e) {
      debugPrint('[MrPlay] _onVideoState error: $e');
    }
  }

  /// Builds and tracks a [Video] from the current watch URL when the
  /// `playerInfo` JS title extraction never reported in, so the mini player /
  /// stats / media controls still appear. Returns the tracked video (or the
  /// already-tracked one, or null when the URL has no video id).
  Video? _trackVideoFromUrl() {
    final existing = ref.read(playerProvider).currentVideo;
    if (existing != null) return existing;
    final url = _videoTabUrl ?? _currentUrl ?? '';
    final idMatch = RegExp(r'[?&]v=([^&]+)').firstMatch(url);
    final String videoId;
    final String thumbnailUrl;
    final String platform;
    if (idMatch != null) {
      videoId = idMatch.group(1)!;
      thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      platform = 'YouTube';
    } else {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty) return null;
      videoId = url;
      thumbnailUrl = '';
      platform = _platformNameFromUrl(uri.host);
    }
    final video = Video(
      id: videoId,
      title: 'Playing video',
      thumbnailUrl: thumbnailUrl,
      videoUrl: url,
      platform: platform,
    );
    if (_videoTabUrl != null) {
      ref.read(playerProvider.notifier).openVideoTab(video);
    } else {
      ref.read(playerProvider.notifier).play(video);
    }
    _userPausedInBackground = false;
    _isMusic = _isMusicUrl(url);
    return video;
  }

  String _platformNameFromUrl(String host) {
    var h = host;
    if (h.startsWith('m.')) {
      h = h.substring(2);
    } else if (h.startsWith('www.')) {
      h = h.substring(4);
    }
    final first = h.split('.').first;
    if (first.isEmpty) return 'Web';
    return '${first[0].toUpperCase()}${first.substring(1)}';
  }

  void _updateNowPlayingThrottled({
    required int positionMs,
    required int durationMs,
    required bool playing,
  }) {
    if (positionMs - _lastNowPlayingMs < 1000) return;
    _lastNowPlayingMs = positionMs;
    // While the system has paused us, freeze the elapsed time in Now Playing
    // so the notification doesn't keep counting up while the video is stopped.
    if (_systemPaused) {
      MediaControlsService.instance.updateProgress(
        position: Duration(seconds: _systemPausedElapsed.toInt()),
        duration: Duration(milliseconds: durationMs),
        isPlaying: false,
      );
      return;
    }
    MediaControlsService.instance.updateProgress(
      position: Duration(milliseconds: positionMs),
      duration: Duration(milliseconds: durationMs),
      isPlaying: playing,
    );
  }

  Future<void> _handleEnded() async {
    if (_endedHandled) return;
    _endedHandled = true;
    final items = await QueueRepository.getAll();
    if (items.isEmpty) return;
    final next = items.first;
    await QueueRepository.remove(next.id);
    exitPiP();
    if (mounted) loadUrl(next.platformUrl);
  }

  void _onRemoteCommand(String command, {Duration? position}) {
    final state = ref.read(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final positionMs = position?.inMilliseconds ?? 0;
    switch (command) {
      case 'play':
        resumePlayback();
        break;
      case 'pause':
        userInitiatedPause();
        break;
      case 'toggle':
        if (state.isPlaying) {
          userInitiatedPause();
        } else {
          resumePlayback();
        }
        break;
      case 'skipForward':
        final next = state.position + const Duration(seconds: 15);
        notifier.seekTo(next);
        controlVideo('seek', position: next.inMilliseconds / 1000.0);
        break;
      case 'skipBackward':
        final prev = state.position - const Duration(seconds: 15);
        final clamped = prev.isNegative ? Duration.zero : prev;
        notifier.seekTo(clamped);
        controlVideo('seek', position: clamped.inMilliseconds / 1000.0);
        break;
      case 'seek':
        if (positionMs > 0) {
          final target = Duration(milliseconds: positionMs);
          notifier.seekTo(target);
          controlVideo('seek', position: target.inMilliseconds / 1000.0);
        }
        break;
    }
  }

  /// Pauses playback as an explicit user action (lock screen / Control Center
  /// / sleep timer). While backgrounded, system-forced pauses are auto-resumed
  /// (for YouTube Music); user pauses must not be fought.
  void userInitiatedPause() {
    _backgroundResumeAllowed = false;
    if (_appIsBackgrounded) _userPausedInBackground = true;
    // Keep the silent loop alive while backgrounded so iOS doesn't suspend
    // the WebView. Without it, Control Center's play button can't reach the
    // webview to resume playback.
    if (!_appIsBackgrounded) {
      BackgroundAudioKeepAlive.instance.stop();
    }
    ref.read(playerProvider.notifier).pause();
    controlVideo('pause');
  }

  /// The system took over our audio (another app, a phone call, a route
  /// change). Pause and latch so the state poll / JS events cannot re-mark
  /// Now Playing as "playing" while the video is actually paused.
  void _systemPause() {
    _systemPaused = true;
    _backgroundResumeAllowed = false;
    // Freeze the elapsed time so Now Playing doesn't keep counting up while
    // the video is actually paused by the system (call / other app).
    _systemPausedElapsed = ref.read(playerProvider).position.inSeconds.toDouble();
    if (_isMusic) BackgroundAudioKeepAlive.instance.stop();
    ref.read(playerProvider.notifier).pause();
    MediaControlsService.instance.setPlaying(false);
    controlVideo('pause');
    // Force-update Now Playing with the frozen elapsed time so the
    // notification immediately shows the correct paused position.
    final dur = ref.read(playerProvider).duration;
    MediaControlsService.instance.updateProgress(
      position: Duration(seconds: _systemPausedElapsed.toInt()),
      duration: dur,
      isPlaying: false,
    );
  }

  /// User-initiated resume (mini player / full player / remote play). Clears
  /// the system-pause latch and resumes playback.
  void resumePlayback() {
    _systemPaused = false;
    _systemPausedElapsed = 0;
    _backgroundResumeAllowed = true;
    _userPausedInBackground = false;
    ref.read(playerProvider.notifier).resume();
    controlVideo('play');
  }

  /// Called by the floating ad banner when a video ad starts (true) or
  /// ends/fails (false). While a video ad is active, audio interruptions from
  /// the ad SDK are ignored so the video is not falsely paused.
  void setAdActive(bool active) {
    if (_adActive == active) return;
    _adActive = active;
    if (active) {
      _wasPlayingBeforeAd = ref.read(playerProvider).isPlaying;
    } else if (_wasPlayingBeforeAd) {
      _wasPlayingBeforeAd = false;
      if (!ref.read(playerProvider).isPlaying && mounted) {
        _systemPaused = false;
        _backgroundResumeAllowed = true;
        ref.read(playerProvider.notifier).resume();
        controlVideo('play');
        _reassertAudioSession();
      }
    }
  }

  /// Shows the mini player: tracks the currently-playing video if needed (so
  /// there is something to display) and collapses the full player. Bound to
  /// the mini-player overlay button in the webview.
  void showMiniPlayer() {
    _trackVideoFromUrl();
    if (ref.read(playerProvider).currentVideo != null) {
      ref.read(playerProvider.notifier).minimize();
    }
  }

  /// Opens (or re-slot) the dedicated video tab onto the given watch URL.
  /// If the tab webview already exists it simply navigates (reloading the new
  /// video); otherwise the URL is stashed and consumed when the tab widget is
  /// built. The tab is expanded and fades in from the bottom so a new video
  /// selected on the browse tab visibly pops the second tab back up.
  void _openVideoTab(String url) {
    if (_videoTabUrl == url) return;
    _videoTabUrl = url;
    _endedHandled = false;
    _unmuteDone = false;
    ref.read(playerProvider.notifier).videoTabActive();
    _videoTabIntro = true;
    // Blank the browse webview since it is fully hidden behind the video tab.
    // This frees ~150 MB of WebContent process memory while watching.
    _blankBrowseWebview();
    _browsePreloaded = false;
    final vc = _videoWebViewController;
    if (vc != null) {
      vc.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } else {
      _pendingVideoUrl = url;
    }
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _videoTabIntro) setState(() => _videoTabIntro = false);
      });
    }
  }

  void _showOptionsModal() {
    final video = ref.read(playerProvider).currentVideo;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.85;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SheetMenuItem(
                      icon: Icons.picture_in_picture_alt,
                      label: 'Picture in Picture',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        togglePictureInPicture();
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.playlist_add,
                      label: 'Add to Playlist',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (video == null) return;
                        _showAddToPlaylistSheet(video);
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.bookmark_border,
                      label: 'Add to Bookmarks',
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        if (video == null) return;
                        final already =
                            await WatchLaterRepository.isQueued(video.id);
                        if (already) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Already in bookmarks'),
                                  duration: Duration(seconds: 1)),
                            );
                          }
                          return;
                        }
                        await WatchLaterRepository.add(FavoriteVideo(
                          id: video.id,
                          title: video.title,
                          channel: video.platform.isEmpty
                              ? 'YouTube'
                              : video.platform,
                          thumbnailUrl: video.thumbnailUrl,
                          platformUrl: video.videoUrl,
                          addedAt: DateTime.now(),
                        ));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Added to bookmarks'),
                                duration: Duration(seconds: 1)),
                          );
                        }
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.bookmarks,
                      label: 'View Bookmarks',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const FavoritesPage()),
                        );
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.bedtime,
                      label: 'Sleep Timer',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Future.delayed(const Duration(milliseconds: 400), () {
                          if (mounted) showSleepTimerSheet(context);
                        });
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.airplay,
                      label: 'AirPlay',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _activeController?.evaluateJavascript(source: '''
                        (function(){
                          var v=document.querySelector('video');
                          if(v&&v.webkitShowPlaybackTargetPicker)
                            v.webkitShowPlaybackTargetPicker();
                        })();
                      ''');
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.share,
                      label: 'Share Link',
                      onTap: () {
                        var shareUrl = video?.videoUrl ?? '';
                        if (shareUrl.isEmpty &&
                            video != null &&
                            video.id.isNotEmpty) {
                          shareUrl =
                              'https://www.youtube.com/watch?v=${video.id}';
                        }
                        if (shareUrl.isEmpty) shareUrl = _currentUrl ?? '';
                        final shareTitle = video?.title ?? 'MrPlay Video';
                        // iPad presents the share sheet as a popover and requires
                        // a source rect, otherwise it silently drops the sheet.
                        final origin = _sharePositionOrigin();
                        Navigator.pop(sheetContext);
                        // Defer Share.share until the bottom sheet's dismiss
                        // animation completes. iOS silently drops a share sheet
                        // presented on a controller mid-dismiss, which is why the
                        // button appeared to do nothing.
                        if (shareUrl.isNotEmpty) {
                          Future.delayed(const Duration(milliseconds: 400), () {
                            Share.share(
                              shareUrl,
                              subject: shareTitle,
                              sharePositionOrigin: origin,
                            );
                          });
                        }
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.settings,
                      label: 'Settings',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SettingsPage()),
                        );
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.file_upload_outlined,
                      label: 'Export Data',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        DataExportService.instance.exportToJson();
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.file_download_outlined,
                      label: 'Import Data',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Share a .json or .csv file to MrPlay to import'),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Returns a screen-anchored rect used as the popover source on iPad, where
  /// [Share.share] requires a non-null `sharePositionOrigin` or it drops the
  /// sheet silently.
  Rect _sharePositionOrigin() {
    final size = MediaQuery.of(context).size;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 1,
      height: 1,
    );
  }

  /// Bottom sheet that lets the user add the current video to an existing
  /// playlist or create a new one.
  void _showAddToPlaylistSheet(Video video) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      'Add to playlist',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add, color: Colors.white70),
                    title: const Text('New playlist',
                        style: TextStyle(color: Colors.white)),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final name = await showDialog<String>(
                        context: context,
                        builder: (_) => const _NewPlaylistDialog(),
                      );
                      if (name == null || name.isEmpty || !mounted) return;
                      final playlist = await PlaylistRepository.create(name);
                      await _addVideoToPlaylist(playlist, video);
                    },
                  ),
                  const Divider(color: Colors.white10, height: 1, indent: 56),
                  Flexible(
                    child: FutureBuilder<List<Playlist>>(
                      future: PlaylistRepository.getAll(),
                      builder: (context, snapshot) {
                        final playlists = snapshot.data ?? const <Playlist>[];
                        if (playlists.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'No playlists yet — create one first.',
                              style:
                                  TextStyle(color: Colors.white54, fontSize: 14),
                            ),
                          );
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: playlists.length,
                          itemBuilder: (context, index) {
                            final playlist = playlists[index];
                            return ListTile(
                              leading: const Icon(Icons.playlist_play,
                                  color: Colors.white70),
                              title: Text(playlist.name,
                                  style: const TextStyle(color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _addVideoToPlaylist(playlist, video);
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _addVideoToPlaylist(Playlist playlist, Video video) async {
    final item = PlaylistItem(
      id: '${playlist.id}::${video.id.isEmpty ? video.videoUrl : video.id}',
      title: video.title.isEmpty ? 'Untitled' : video.title,
      thumbnailUrl: video.thumbnailUrl,
      platformUrl: video.videoUrl,
      platformName: video.platform.isEmpty ? 'YouTube' : video.platform,
      playlistId: playlist.id,
    );
    final added = await PlaylistRepository.addItem(playlist.id, item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added
            ? 'Added to "${playlist.name}"'
            : 'Already in "${playlist.name}"'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Full cleanup: pauses the video, cancels timers, stops audio keep-alive,
  /// clears now-playing, flushes stats, and dismisses the player state. When a
  /// video tab is open it is closed too, so playback fully stops.
  void closePlayer() {
    controlVideo('pause');
    BackgroundAudioKeepAlive.instance.stop();
    _systemPaused = false;
    _systemPausedElapsed = 0;
    _stopStatePoll();
    _loadingTimer?.cancel();
    _loadingTimer = null;
    _nowPlayingThrottle?.cancel();
    _nowPlayingThrottle = null;
    _videoTabUrl = null;
    _videoWebViewController = null;
    _pendingVideoUrl = null;
    _tabSwipeOffset = 0;
    PlaybackStatsService.instance.flush();
    MediaControlsService.instance.clearNowPlaying();
    ref.read(playerProvider.notifier).dismiss();
    if (mounted) setState(() {});
  }

  void controlVideo(String action, {double? position}) {
    final controller = _activeController;
    if (controller == null) return;
    switch (action) {
      case 'play':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = $_activeVideoJs;
            if (v) v.play().catch(function(){});
          })();
        ''');
        break;
      case 'pause':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = $_activeVideoJs;
            if (v) v.pause();
          })();
        ''');
        break;
      case 'seek':
        if (position != null) {
          controller.evaluateJavascript(source: '''
            (function() {
              var v = $_activeVideoJs;
              if (v) v.currentTime = $position;
            })();
          ''');
        }
        break;
      case 'toggleCaptions':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = $_activeVideoJs;
            if (!v || !v.textTracks || v.textTracks.length === 0) return;
            var anyShown = false;
            for (var i = 0; i < v.textTracks.length; i++) {
              if (v.textTracks[i].mode === 'showing') { anyShown = true; break; }
            }
            for (var j = 0; j < v.textTracks.length; j++) {
              v.textTracks[j].mode = anyShown ? 'hidden' : 'showing';
            }
          })();
        ''');
        break;
      case 'fullscreen':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = $_activeVideoJs;
            if (!v) return;
            if (v.requestFullscreen) {
              if (document.fullscreenElement) {
                document.exitFullscreen().catch(function(){});
              } else {
                v.requestFullscreen().catch(function(){});
              }
            } else if (v.webkitEnterFullscreen) {
              v.webkitEnterFullscreen();
            }
          })();
        ''');
        break;
      case 'enterFullscreen':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = $_activeVideoJs;
            if (!v) return;
            if (v.requestFullscreen) {
              if (!document.fullscreenElement) {
                v.requestFullscreen().catch(function(){});
              }
            } else if (v.webkitEnterFullscreen) {
              try { v.webkitEnterFullscreen(); } catch (e) {}
            }
          })();
        ''');
        break;
      case 'exitFullscreen':
        controller.evaluateJavascript(source: '''
          (function() {
            if (document.fullscreenElement && document.exitFullscreen) {
              document.exitFullscreen().catch(function(){});
            }
            var v = $_activeVideoJs;
            if (v && v.webkitExitFullscreen) {
              try { v.webkitExitFullscreen(); } catch (e) {}
            }
          })();
        ''');
        break;
    }
  }

  /// Un-mutes the actively playing video. YouTube sometimes starts playback
  /// muted (or the user previously muted it), and the "tap to unmute" overlay
  /// needs a tap. We bypass the UI by directly clearing `muted` on the video
  /// element(s) and restoring volume. Returns whether the active video is now
  /// audible, so callers can retry until it is (a single fire-and-forget shot
  /// leaves some videos muted when the element wasn't ready yet).
  Future<bool> _unmuteVideo() async {
    final controller = _activeController;
    if (controller == null) return false;
    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          (function() {
            var videos = document.querySelectorAll('video');
            var main = null;
            for (var i = 0; i < videos.length; i++) {
              if (!videos[i].paused && !videos[i].ended) {
                main = videos[i];
                break;
              }
            }
            if (!main && videos.length > 0) main = videos[0];
            if (!main) return { audible: false };
            if (main.muted || main.volume === 0) {
              main.muted = false;
              main.defaultMuted = false;
              main.volume = 1;
            }
            return { audible: !main.muted && main.volume > 0 };
          })();
        ''',
      );
      final value = result?.value;
      return value is Map && value['audible'] == true;
    } catch (e) {
      debugPrint('[MrPlay] _unmuteVideo error: $e');
      return false;
    }
  }

  void loadUrl(String url) {
    if (_routesToVideoTab(url)) {
      // Playing a saved/history video from an overlay page (Library,
      // Watch History): reveal the webview layer BEFORE opening the video
      // tab. isReady gates this whole widget's render, so without it the
      // video tab would be built invisibly behind the hub.
      _loadingTimer?.cancel();
      setState(() {
        isReady = true;
        _isLoading = false;
      });
      PersistentWebViewState.hubVisible.value = false;
      _openVideoTab(url);
      return;
    }
    _loadingTimer?.cancel();
    _pendingUrl = url;
    if (_webViewController != null) {
      _webViewController!.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
    }
    setState(() {
      isReady = true;
      _isLoading = true;
    });
    PersistentWebViewState.hubVisible.value = false;
    _endedHandled = false;
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  /// Plays a list of items one-by-one. The first URL is loaded immediately and
  /// the rest are placed in the playback queue, which [_handleEnded] advances
  /// through automatically as each item finishes.
  void playSequentially(List<QueueItem> items) {
    if (items.isEmpty) return;
    // Clear any existing manual queue so the playlist plays in order.
    QueueRepository.clear().then((_) async {
      for (var i = 1; i < items.length; i++) {
        await QueueRepository.add(items[i]);
      }
      if (mounted) loadUrl(items.first.platformUrl);
    });
  }

  void _onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (request.isForMainFrame != false) {
      if (mounted) {
        setState(
            () => _loadError = 'Could not load the page: ${error.description}');
      }
    }
  }

  void _onReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse response,
  ) {
    if (request.isForMainFrame != false) {
      if (mounted) {
        setState(() {
          _loadError = 'Server error ${response.statusCode ?? 'unknown'}';
        });
      }
    }
  }

  void _retryLoad() {
    if (!mounted) return;
    setState(() => _loadError = null);
    _webViewController?.reload();
  }

  /// Enters native Picture-in-Picture for the actively-playing video. Only
  /// called from explicit user actions (PiP button / swipe-down), so iOS
  /// presents the real floating window.
  void enterPiP() {
    _activeController?.evaluateJavascript(source: '''
      (function() {
        var video = $_activeVideoJs;
        if (!video) return;
        if (video.requestPictureInPicture) {
          video.requestPictureInPicture().catch(function(){});
        } else if (video.webkitSetPresentationMode) {
          if (video.webkitPresentationMode !== 'picture-in-picture') {
            video.webkitSetPresentationMode('picture-in-picture');
          }
        }
      })();
    ''');
  }

  /// Brings the video back inline after PiP. Uses only the clean API call —
  /// no DOM surgery, so it can't corrupt YouTube's MediaSource pipeline.
  void exitPiP() {
    _activeController?.evaluateJavascript(source: '''
      (function() {
        var video = $_activeVideoJs;
        if (!video) return;
        if (document.exitPictureInPicture && document.pictureInPictureElement) {
          document.exitPictureInPicture().catch(function(){});
        } else if (video.webkitSetPresentationMode &&
                   video.webkitPresentationMode === 'picture-in-picture') {
          video.webkitSetPresentationMode('inline');
        }
      })();
    ''');
  }

  void togglePictureInPicture() {
    _activeController?.evaluateJavascript(source: '''
      (function() {
        var video = $_activeVideoJs;
        if (!video) return;
        if (video.requestPictureInPicture) {
          if (document.pictureInPictureElement) {
            document.exitPictureInPicture().catch(function(){});
          } else {
            video.requestPictureInPicture().catch(function(){});
          }
        } else if (video.webkitSetPresentationMode) {
          video.webkitSetPresentationMode(
            video.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture'
          );
        }
      })();
    ''');
  }

  /// Restores the video inline after phantom PiP (used on background to keep
  /// audio alive). Event-driven: waits for webkitpresentationmodechanged to
  /// confirm 'inline', verifies rendering, and reloads the page as a last
  /// resort — no DOM surgery, which corrupts YouTube's MediaSource pipeline.
  Future<void> _restoreVideoInline() async {
    final controller = _activeController;
    if (controller == null) return;
    try {
      final result = await controller.callAsyncJavaScript(functionBody: '''
        var videos = document.querySelectorAll('video');
        var video = null;
        for (var i = 0; i < videos.length; i++) {
          if (!videos[i].paused && !videos[i].ended) { video = videos[i]; break; }
        }
        if (!video && videos.length > 0) video = videos[0];
        if (!video) return { ok: true, reason: 'no-video' };
        if (!video.webkitSetPresentationMode ||
            video.webkitPresentationMode !== 'picture-in-picture') {
          return { ok: true, reason: 'already-inline' };
        }
        return new Promise(function(resolve) {
          var done = false;
          var timer = setTimeout(function() {
            if (done) return;
            done = true;
            video.removeEventListener('webkitpresentationmodechanged', onMode);
            resolve({ ok: false, reason: 'timeout' });
          }, 1500);
          function onMode() {
            if (video.webkitPresentationMode !== 'inline') return;
            if (done) return;
            done = true;
            clearTimeout(timer);
            video.removeEventListener('webkitpresentationmodechanged', onMode);
            var rendered = video.videoWidth > 0;
            resolve({ ok: rendered, reason: rendered ? 'inline' : 'no-render' });
          }
          video.addEventListener('webkitpresentationmodechanged', onMode);
          try {
            video.webkitSetPresentationMode('inline');
          } catch (e) {
            if (done) return;
            done = true;
            clearTimeout(timer);
            video.removeEventListener('webkitpresentationmodechanged', onMode);
            resolve({ ok: false, reason: 'api-error' });
          }
        });
      ''');
      final value = result?.value;
      final ok = value is Map && value['ok'] == true;
      if (!ok) {
        debugPrint('[MrPlay] inline restore failed, reloading');
        _activeController?.reload();
      }
    } catch (e) {
      debugPrint('[MrPlay] _restoreVideoInline error: $e');
      _activeController?.reload();
    }
  }

  /// Enters phantom PiP on background and makes sure the video is actually
  /// playing inside the PiP session. iOS pauses the webview video when the app
  /// backgrounds; the PiP handoff alone leaves it paused (no audio). We wait for
  /// the mode-change event, then resume playback so the PiP/AVFoundation session
  /// keeps the audio alive.
  Future<void> _enterPhantomPiP() async {
    final controller = _activeController;
    if (controller == null) return;
    try {
      final result = await controller.callAsyncJavaScript(functionBody: '''
        var videos = document.querySelectorAll('video');
        var video = null;
        for (var i = 0; i < videos.length; i++) {
          if (!videos[i].paused && !videos[i].ended) { video = videos[i]; break; }
        }
        if (!video && videos.length > 0) video = videos[0];
        if (!video || !video.webkitSetPresentationMode) return { ok: false, reason: 'no-video' };
        try { video.disablePictureInPicture = false; video.removeAttribute('disablepictureinpicture'); } catch (e) {}
        if (video.webkitPresentationMode !== 'picture-in-picture') {
          await new Promise(function(resolve) {
            var timer = setTimeout(function() {
              cleanup();
              resolve();
            }, 1500);
            function onMode() {
              if (video.webkitPresentationMode === 'picture-in-picture') {
                cleanup();
                resolve();
              }
            }
            function cleanup() {
              clearTimeout(timer);
              video.removeEventListener('webkitpresentationmodechanged', onMode);
            }
            video.addEventListener('webkitpresentationmodechanged', onMode);
            try {
              video.webkitSetPresentationMode('picture-in-picture');
            } catch (e) {
              cleanup();
              resolve();
            }
          });
        }
        if (video.paused) {
          for (var attempt = 0; attempt < 2; attempt++) {
            try {
              await video.play();
              break;
            } catch (e) {
              if (attempt === 1) return { ok: false, reason: 'play-rejected' };
              await new Promise(function(r) { setTimeout(r, 200); });
            }
          }
        }
        return { ok: !video.paused, reason: video.paused ? 'still-paused' : 'playing' };
      ''');
      final value = result?.value;
      if (value is Map && value['ok'] != true) {
        debugPrint('[MrPlay] phantom PiP failed: ${value['reason']}');
      }
    } catch (_) {
      // WebContent may already be suspended; nothing else we can do from Dart.
    }
  }

  /// Polls the webview for the live video position/duration from the Dart side.
  /// While the full player overlays the webview, iOS can throttle the page's
  /// own timers/events, so the JS `reportState` heartbeat may stop firing and
  /// the seek slider / timer freeze. This keeps `position`/`duration` fresh
  /// regardless of page-side throttling.
  void _startStatePoll() {
    _statePoll?.cancel();
    _statePoll = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollVideoState(),
    );
  }

  void _stopStatePoll() {
    _statePoll?.cancel();
    _statePoll = null;
  }

  Future<void> _pollVideoState() async {
    final controller = _activeController;
    if (controller == null) return;
    try {
      final result = await controller.evaluateJavascript(source: '''
        (function() {
          var videos = document.querySelectorAll('video');
          var v = null;
          for (var i = 0; i < videos.length; i++) {
            if (!videos[i].paused && !videos[i].ended) { v = videos[i]; break; }
          }
          if (!v && videos.length > 0) v = videos[0];
          if (!v) return null;
          var pipStuck = false;
          var pipActive = false;
          try {
            pipStuck = (typeof v.webkitPresentationMode !== 'undefined') &&
                       v.webkitPresentationMode === 'picture-in-picture';
            pipActive = (typeof document.pictureInPictureElement !== 'undefined' &&
                         !!document.pictureInPictureElement);
          } catch (e) {}
          return {
            playing: !v.paused && !v.ended,
            position: isFinite(v.currentTime) ? v.currentTime : 0,
            duration: isFinite(v.duration) ? v.duration : 0,
            ended: !!v.ended,
            pip: pipStuck || pipActive,
            pipActive: pipActive,
            pipStuck: pipStuck && !pipActive
          };
        })();
      ''');
      if (result is Map) {
        _onVideoState(Map<String, dynamic>.from(result));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playerProvider, (prev, next) {
      final videoAppeared =
          prev?.currentVideo == null && next.currentVideo != null;
      final videoGone = prev?.currentVideo != null && next.currentVideo == null;
      if (videoAppeared) _startStatePoll();
      if (videoGone) _stopStatePoll();
      // Collapsed -> expanded: re-attach the JS swipe listeners. After a
      // collapse cycle WKWebView can detach/reset its touch handlers, so the
      // custom user script alone is no longer enough — re-inject it (it
      // cleans up its own previous listeners, so it's safe to run repeatedly).
      final reExpanded = prev?.isVideoTab == true &&
          prev?.isMinimized == true &&
          next.isVideoTab &&
          next.isMinimized == false;
      if (reExpanded) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          try {
            _videoWebViewController?.evaluateJavascript(
              source: VideoTabJS.swipeCollapseScript,
            );
          } catch (_) {}
        });
      }
    });
    if (!isReady) return const SizedBox.shrink();

    final playerState = ref.watch(playerProvider);
    final videoTabCollapsed = _videoTabUrl != null &&
        playerState.isVideoTab &&
        playerState.isMinimized;

    // The collapsed video tab is a 64px Flutter mini bar sitting at the same
    // height as YouTube's bottom nav (52 + home indicator). When it's visible,
    // lift the bottom-right floating buttons so they sit exactly above that
    // bar instead of overlapping it.
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const double bottomNavHeight = 52;
    const double miniBarHeight = 64;
    final double buttonsBottomBase = videoTabCollapsed
        ? bottomNavHeight + bottomPadding + miniBarHeight + 12
        : 80;

    return Stack(
      children: [
        // Browse tab — kept offstage until it actually holds a page. Playing
        // straight from Library/History never browsed anything, so an empty
        // WKWebView would paint as a white sheet behind the collapsed video
        // tab; hiding it lets the HubPage show through instead.
        Positioned.fill(
          child: Offstage(
            offstage: _currentUrl == null,
            child: InAppWebView(
            initialUserScripts: UnmodifiableListView([
              if (_adBlockEnabled)
                UserScript(
                  source: ContentBlockerJS.stripAdDataScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              if (_adBlockEnabled)
                UserScript(
                  source: ContentBlockerJS.adRequestBlockerScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              if (_adBlockEnabled)
                UserScript(
                  source: ContentBlockerJS.genericAdBlockerScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              if (_adBlockEnabled)
                UserScript(
                  source: ContentBlockerJS.adFallbackSkipScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
              UserScript(
                source: YouTubeJS.visibilityKeepAliveScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
              UserScript(
                source: YouTubeJS.appBannerRemoverScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
              UserScript(
                source: YouTubeJS.playerControlsScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
              UserScript(
                source: MediaObserverJS.genericObserverScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              allowBackgroundAudioPlaying: _backgroundAudioEnabled,
              allowsPictureInPictureMediaPlayback: _backgroundAudioEnabled,
              allowsAirPlayForMediaPlayback: true,
              isFraudulentWebsiteWarningEnabled: false,
              userAgent:
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
            ),
            onWebViewCreated: _onWebViewCreated,
            onLoadStart: _onLoadStart,
            onLoadStop: _onLoadStop,
            onUpdateVisitedHistory: _onBrowseVisitedHistory,
            onReceivedError: _onReceivedError,
            onReceivedHttpError: _onReceivedHttpError,
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url;
              if (url != null) {
                final scheme = url.scheme.toLowerCase();
                if (scheme == 'http' ||
                    scheme == 'https' ||
                    scheme == 'about' ||
                    scheme == 'file') {
                  return NavigationActionPolicy.ALLOW;
                }
                if (scheme == 'javascript' ||
                    scheme == 'data' ||
                    scheme == 'blob') {
                  return NavigationActionPolicy.CANCEL;
                }
              }
              return NavigationActionPolicy.ALLOW;
            },
            onCreateWindow: (controller, createWindowAction) async {
              final url = createWindowAction.request.url;
              if (url == null) return false;
              final host = url.host;
              if (_isAdDomain(host)) return false;
              controller.loadUrl(urlRequest: URLRequest(url: url));
              return false;
            },
            onWebContentProcessDidTerminate: (controller) async {
              debugPrint('[MrPlay] Browse WebContent process terminated — reloading');
              if (mounted) {
                setState(() => _isLoading = true);
                await Future.delayed(const Duration(milliseconds: 500));
                if (mounted) {
                  controller.reload();
                }
              }
            },
            ),
          ),
        ),
        // Tab 2 — dedicated video tab. Rendered on top while "full", fades
        // away (but stays alive) when minimized so the browse webview below
        // is visible and interactive. Never disposed while playing: that would
        // cut the audio. On first appearance it fades in from the bottom
        // (_videoTabIntro), matching the swipe-down collapse direction.
        if (_videoTabUrl != null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: videoTabCollapsed,
              child: AnimatedOpacity(
                opacity: (videoTabCollapsed || _videoTabIntro) ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: AnimatedSlide(
                  offset: _videoTabIntro
                      ? const Offset(0, 0.35)
                      : (videoTabCollapsed ? const Offset(0, 0.25) : Offset.zero),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: InAppWebView(
                    key: const ValueKey('video-tab'),
                    initialUrlRequest: URLRequest(url: WebUri(_videoTabUrl!)),
                    initialUserScripts: UnmodifiableListView([
                      if (_adBlockEnabled)
                        UserScript(
                          source: ContentBlockerJS.stripAdDataScript,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      if (_adBlockEnabled)
                        UserScript(
                          source: ContentBlockerJS.adRequestBlockerScript,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      if (_adBlockEnabled)
                        UserScript(
                          source: ContentBlockerJS.genericAdBlockerScript,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      if (_adBlockEnabled)
                        UserScript(
                          source: ContentBlockerJS.adFallbackSkipScript,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      UserScript(
                        source: YouTubeJS.visibilityKeepAliveScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      UserScript(
                        source: VideoTabJS.headerRemoverScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      UserScript(
                        source: VideoTabJS.swipeCollapseScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      UserScript(
                        source: YouTubeJS.appBannerRemoverScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      UserScript(
                        source: YouTubeJS.playerControlsScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      UserScript(
                        source: MediaObserverJS.genericObserverScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                    ]),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      allowsInlineMediaPlayback: true,
                      mediaPlaybackRequiresUserGesture: false,
                      allowBackgroundAudioPlaying: _backgroundAudioEnabled,
                      allowsPictureInPictureMediaPlayback:
                          _backgroundAudioEnabled,
                      allowsAirPlayForMediaPlayback: true,
                      isFraudulentWebsiteWarningEnabled: false,
                      userAgent:
                          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
                    ),
                    onWebViewCreated: _onVideoWebViewCreated,
                    onLoadStart: _onVideoLoadStart,
                    onLoadStop: _onLoadStop,
                    onUpdateVisitedHistory: _onVideoVisitedHistory,
                    onReceivedError: _onReceivedError,
                    onReceivedHttpError: _onReceivedHttpError,
                    shouldOverrideUrlLoading:
                        (controller, navigationAction) async {
                      final url = navigationAction.request.url;
                      if (url != null) {
                        final scheme = url.scheme.toLowerCase();
                        if (scheme == 'http' ||
                            scheme == 'https' ||
                            scheme == 'about' ||
                            scheme == 'file') {
                          return NavigationActionPolicy.ALLOW;
                        }
                        if (scheme == 'javascript' ||
                            scheme == 'data' ||
                            scheme == 'blob') {
                          return NavigationActionPolicy.CANCEL;
                        }
                      }
                      return NavigationActionPolicy.ALLOW;
                    },
                    onCreateWindow: (controller, createWindowAction) async {
                      final url = createWindowAction.request.url;
                      if (url == null) return false;
                      final host = url.host;
                      if (_isAdDomain(host)) return false;
                      controller.loadUrl(urlRequest: URLRequest(url: url));
                      return false;
                    },
                    onWebContentProcessDidTerminate: (controller) async {
                      debugPrint('[MrPlay] Video WebContent process terminated — reloading');
                      if (mounted) {
                        setState(() => _isLoading = true);
                        await Future.delayed(const Duration(milliseconds: 500));
                        if (mounted) {
                          controller.reload();
                        }
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        if (_loadError != null && !_isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: CustomErrorWidget(
                message: _loadError!,
                onRetry: _retryLoad,
              ),
            ),
          ),
        if (_isLoading)
          Positioned(
            top: 60,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                ),
              ),
            ),
          ),
        // Swipe-down handle shown only while the video tab is expanded. Full-
        // width strip (not just the pill) so a swipe starting anywhere along
        // the top of the tab collapses it, matching the arrow button.
        if (_videoTabUrl != null && !videoTabCollapsed)
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            left: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _onTabSwipeUpdate,
              onVerticalDragEnd: _onTabSwipeEnd,
              onTap: _minimizeVideoTab,
              child: Container(
                height: 44,
                width: double.infinity,
                color: Colors.transparent,
                alignment: Alignment.center,
                child: Transform.translate(
                  offset: Offset(0, _tabSwipeOffset),
                  child: AnimatedOpacity(
                    opacity: _tabSwipeOffset > 20 ? 0.3 : 1.0,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      width: 128,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white70, size: 26),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          bottom: buttonsBottomBase + 126,
          right: 16,
          child: GestureDetector(
            onTap: _showOptionsModal,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.more_horiz,
                  color: Colors.white, size: 24),
            ),
          ),
        ),
        Positioned(
          bottom: buttonsBottomBase + 84,
          right: 16,
          child: GestureDetector(
            onTap: showMiniPlayer,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.play_circle_outline,
                  color: Colors.white, size: 24),
            ),
          ),
        ),
        Positioned(
          bottom: buttonsBottomBase + 42,
          right: 16,
          child: GestureDetector(
            onTap: togglePictureInPicture,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.picture_in_picture_alt,
                  color: Colors.white, size: 24),
            ),
          ),
        ),
        Positioned(
          bottom: buttonsBottomBase,
          right: 16,
          child: GestureDetector(
            onTap: _goToHub,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 24),
            ),
          ),
        ),
      ],
    );
  }

  /// Full reset back to the hub: pauses playback, tears down the video tab
  /// (if any), blanks the browse webview, and hides the whole webview layer so
  /// the HubPage (below in the app Stack) becomes visible again.
  void _goToHub() {
    controlVideo('pause');
    BackgroundAudioKeepAlive.instance.stop();
    _systemPaused = false;
    _stopStatePoll();
    _loadingTimer?.cancel();
    _loadingTimer = null;
    _nowPlayingThrottle?.cancel();
    _nowPlayingThrottle = null;
    _videoTabUrl = null;
    _videoWebViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
    _videoWebViewController = null;
    _pendingVideoUrl = null;
    _tabSwipeOffset = 0;
    _browsePreloaded = false;
    _lastBrowseUrl = null;
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
    _webViewController = null;
    _currentUrl = null;
    PlaybackStatsService.instance.flush();
    MediaControlsService.instance.clearNowPlaying();
    ref.read(playerProvider.notifier).dismiss();
    if (mounted) {
      setState(() {
        isReady = false;
        _isLoading = false;
        _loadError = null;
      });
    }
    PersistentWebViewState.hubVisible.value = true;
  }

  /// Public session reset for the app shell (e.g. backgrounded session
  /// expiry). Returns the user to the hub with all playback torn down.
  void resetToHub() => _goToHub();

  void _minimizeVideoTab() {
    if (_videoTabUrl == null) return;
    _tabSwipeOffset = 0;
    ref.read(playerProvider.notifier).minimize();
    // Ensure the browse webview is loaded by the time the video slides away.
    // If a preload was triggered during the swipe it may already be loading;
    // otherwise kick one off now so there is no white-flash.
    if (!_browsePreloaded && _lastBrowseUrl != null) {
      _restoreBrowseWebview();
    }
    _browsePreloaded = false;
  }

  void _onTabSwipeUpdate(DragUpdateDetails details) {
    setState(() {
      _tabSwipeOffset += details.delta.dy;
      if (_tabSwipeOffset < 0) _tabSwipeOffset = 0;
    });
    // When the user swipes down (positive delta) and the browse webview was
    // blanked to save memory, start loading it immediately so it is ready by
    // the time the video tab finishes sliding away. This avoids the white-
    // flash that would otherwise appear behind the minimizing video.
    if (details.delta.dy > 0 &&
        !_browsePreloaded &&
        _currentUrl == null &&
        _lastBrowseUrl != null &&
        _webViewController != null) {
      _browsePreloaded = true;
      _restoreBrowseWebview();
    }
  }

  void _onTabSwipeEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 350 || _tabSwipeOffset > 110) {
      _minimizeVideoTab();
    } else {
      setState(() => _tabSwipeOffset = 0);
    }
  }
}

class _SheetMenuItem extends StatelessWidget {
  const _SheetMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}

class _NewPlaylistDialog extends StatefulWidget {
  const _NewPlaylistDialog();

  @override
  State<_NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<_NewPlaylistDialog> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'My playlist',
        ),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _nameController.text.trim()),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
