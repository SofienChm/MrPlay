import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:audio_session/audio_session.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/youtube_js.dart';
import '../../core/constants/content_blocker_js.dart';
import '../../core/constants/media_observer_js.dart';
import '../../core/constants/webview_ad_blocker.dart';
import '../../models/video.dart';
import '../../providers/player_provider.dart';
import '../../services/background_audio_keep_alive.dart';
import '../../services/media_controls_service.dart';
import '../../services/picture_in_picture_service.dart';
import '../../services/playback_stats_service.dart';
import '../../services/data_export_service.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/watch_later_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/models/favorite_video.dart';
import '../../presentation/pages/settings_page.dart';
import '../../presentation/pages/favorites_page.dart';
import '../../widgets/sleep_timer_sheet.dart';
import '../../widgets/add_to_playlist_sheet.dart';
import 'error_widget.dart';

class PersistentWebView extends ConsumerStatefulWidget {
  const PersistentWebView({super.key});

  @override
  ConsumerState<PersistentWebView> createState() => PersistentWebViewState();
}

class PersistentWebViewState extends ConsumerState<PersistentWebView>
    with WidgetsBindingObserver {
  /// Whether the webview layer occupies the screen (hub hidden). Drives the
  /// floating banner in app.dart so the hub's own inline banner stays the only
  /// ad visible while no platform is open.
  static final ValueNotifier<bool> layerVisible = ValueNotifier<bool>(false);

  InAppWebViewController? _webViewController;
  InAppWebViewController? _videoWebViewController;
  String? _videoTabUrl;
  String? _pendingVideoUrl;
  double _tabSwipeOffset = 0;
  bool _waitingToGoBack = false;
  bool _videoTabIntro = false;
  bool _unmuteDone = false;
  bool isReady = false;
  bool _isLoading = false;

  /// True from the moment a platform is tapped on the hub until its first page
  /// finishes loading: drives the full-screen loader (the corner spinner is
  /// used for subsequent in-platform navigations).
  bool _platformLoading = false;
  String? _pendingUrl;
  String? _currentUrl;
  String? _loadError;
  InAppWebViewController? _errorController;
  Timer? _loadingTimer;
  Timer? _platformLoadingTimeout;
  Timer? _nowPlayingThrottle;
  bool _endedHandled = false;
  bool _appIsBackgrounded = false;
  // Whether a system-forced pause (iOS suspends the webview's video when the
  // app backgrounds / the screen locks) may be auto-resumed to keep audio
  // playing. User-initiated pauses (lock screen, Control Center, sleep timer)
  // clear this so they are not fought.
  bool _backgroundResumeAllowed = false;
  // "Block ads & trackers" toggle (Settings → Privacy & Security → Toggles).
  // On by default; gates both the JS content blockers and the network-level
  // WebViewAdBlocker.
  bool _adBlockEnabled = true;
  // Groups the ad-block user scripts so they can be added/removed at runtime
  // when the "Block ads & trackers" toggle is flipped (no app restart).
  static const String _adBlockScriptGroup = 'mrplay_adblock';
  // "Background audio" toggle. On by default: audio keeps playing when the
  // app is backgrounded. Gates the WebView background-audio settings,
  // auto-resume after system-forced pauses, and the native foreground service.
  bool _backgroundAudioEnabled = true;
  bool _userPausedInBackground = false;
  int _lastNowPlayingMs = 0;
  bool? _lastReportedPlaying;
  Timer? _alignmentWatchdog;
  Timer? _statePoll;
  bool _pollInFlight = false;
  // Whether the active PiP session was explicitly requested by the user (PiP
  // button / swipe-down-to-PiP). iOS can leave a video stuck in PiP
  // presentation mode after the PiP window is dismissed - the in-page player
  // then stays black while audio and the HTML controls keep working. PiP
  // reports that were NOT requested are forced back inline (see
  // [_onVideoState]); requested ones are left alone.
  bool _pipRequestedByUser = false;
  bool _lastReportedPip = false;

  // When a "next/prev" remote command navigates to a new YouTube video, the
  // video autoplays muted (no user gesture). These drive a short unmute retry
  // loop after the new page loads.
  bool _unmuteNextLoad = false;
  Timer? _unmuteTimer;

  /// True when the video is actively in PiP (user or auto-background on iOS;
  /// the native activity PiP overlay on Android).
  bool get isInPictureInPicture => Platform.isAndroid
      ? PictureInPictureService.instance.isInPip.value
      : _pipRequestedByUser;

  /// JS that resolves the actively-playing `<video>` (falling back to the
  /// first one), so controls target the real playback element rather than a
  /// stale/ad/preview element that `querySelector` may hit. We restrict to
  /// `<video>` (matching the iOS app) so YouTube Music's `<audio>` playback is
  /// left to the native site and never surfaces our mini player / controls.
  static const String _activeVideoJs = '''
    (function() {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        if (!videos[i].paused && !videos[i].ended) return videos[i];
      }
      return videos.length > 0 ? videos[0] : null;
    })()
  ''';

  /// Platform-specific mobile user agent. The iOS UA makes the YouTube mobile
  /// site serve iOS-only HTML/JS (webkit presentation modes); Android needs a
  /// Chrome Android UA so the standard PiP API and media controls are used.
  static String _userAgent() {
    if (Platform.isAndroid) {
      return 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
    }
    return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 '
        'Safari/604.1';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MediaControlsService.instance.setRemoteCommandHandler(_onRemoteCommand);
    PictureInPictureService.instance.isInPip.addListener(_onPipModeChanged);
    _subscribeToAudioInterruptions();
    _subscribeToBecomingNoisy();
    _loadToggleSettings();
  }

  /// Reads the "Block ads & trackers" and "Background audio" preferences.
  /// Both default to enabled.
  Future<void> _loadToggleSettings() async {
    final adBlock = await SettingsRepository.getAdBlockEnabled();
    final backgroundAudio =
        await SettingsRepository.getBackgroundAudioEnabled();
    if (!mounted) return;
    setState(() {
      _adBlockEnabled = adBlock;
      _backgroundAudioEnabled = backgroundAudio;
    });
    _pushBackgroundAudioToNative();
  }

  /// Tells the native side whether the foreground service / media notification
  /// may run (Android background audio). No-op on iOS (no handler there).
  Future<void> _pushBackgroundAudioToNative() async {
    try {
      await MediaControlsService.instance
          .setBackgroundAudioEnabled(_backgroundAudioEnabled);
    } catch (_) {}
  }

  /// Re-applies the ad-block and background-audio settings without an app
  /// restart, after the user toggles them in Settings (Settings → Toggles).
  /// Mirrors the iOS build: ad-block scripts are injected into the live
  /// webviews (and evaluated on the current pages) when enabled, and removed
  /// (for future loads) when disabled.
  Future<void> applySettingsChanges() async {
    final adBlock = await SettingsRepository.getAdBlockEnabled();
    final backgroundAudio =
        await SettingsRepository.getBackgroundAudioEnabled();
    if (adBlock != _adBlockEnabled) {
      _adBlockEnabled = adBlock;
      if (mounted) setState(() {});
      await _applyAdBlockRuntime();
    }
    if (backgroundAudio != _backgroundAudioEnabled) {
      _backgroundAudioEnabled = backgroundAudio;
      if (mounted) setState(() {});
      _pushBackgroundAudioToNative();
    }
  }

  /// Applies (or removes) the ad-block user scripts on the already-created
  /// webviews. Runtime-added scripts only run on the next document start, so
  /// when enabling we also evaluate each script — plus a scrub of the already
  /// loaded player response — on the current page.
  Future<void> _applyAdBlockRuntime() async {
    const scripts = [
      ContentBlockerJS.playerAdsStripperScript,
      ContentBlockerJS.adRequestBlockerScript,
      ContentBlockerJS.genericAdBlockerScript,
      ContentBlockerJS.adFallbackSkipScript,
    ];
    for (final controller in [_webViewController, _videoWebViewController]) {
      if (controller == null) continue;
      try {
        if (_adBlockEnabled) {
          await controller.addUserScripts(
            userScripts: scripts
                .map((source) => UserScript(
                      source: source,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      groupName: _adBlockScriptGroup,
                    ))
                .toList(),
          );
          for (final source in scripts) {
            try {
              await controller.evaluateJavascript(source: source);
            } catch (_) {}
          }
          // Scrub any player response already on the current page so an ad slot
          // that was captured before the scripts were applied is cleaned too.
          try {
            await controller.evaluateJavascript(
              source: ContentBlockerJS.scrubExistingPlayerResponseScript,
            );
          } catch (_) {}
        } else {
          await controller.removeUserScriptsByGroupName(
            groupName: _adBlockScriptGroup,
          );
        }
      } catch (e) {
        debugPrint('[MrPlay] apply ad-block runtime failed: $e');
      }
    }
  }

  /// Another app has taken the audio session. Pause playback and update the
  /// player state / Now Playing so notifications don't keep showing "playing"
  /// while the video is actually paused. When the interruption ends the webview
  /// stays paused; the user resumes explicitly.
  Future<void> _subscribeToAudioInterruptions() async {
    try {
      final session = await AudioSession.instance;
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (!event.begin || !mounted) return;
        if (ref.read(playerProvider).isPlaying) {
          ref.read(playerProvider.notifier).pause();
          MediaControlsService.instance.setPlaying(false);
          controlVideo('pause');
        }
      });
    } catch (_) {}
  }

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;

  /// Android fires ACTION_AUDIO_BECOMING_NOISY when the audio output falls
  /// back to the speaker — headphones unplugged or a Bluetooth audio device
  /// disconnected. Pause playback (as an explicit user action, so it is not
  /// auto-resumed in the background).
  Future<void> _subscribeToBecomingNoisy() async {
    try {
      final session = await AudioSession.instance;
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        if (!mounted) return;
        userInitiatedPause();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    PictureInPictureService.instance.isInPip.removeListener(_onPipModeChanged);
    WidgetsBinding.instance.removeObserver(this);
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    _loadingTimer?.cancel();
    _platformLoadingTimeout?.cancel();
    _nowPlayingThrottle?.cancel();
    _alignmentWatchdog?.cancel();
    _statePoll?.cancel();
    _unmuteTimer?.cancel();
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
      _pipRequestedByUser = false;
      _lastReportedPip = false;
      if (Platform.isIOS) {
        Future.delayed(const Duration(milliseconds: 3000), ensureVideoVisible);
      }
    }
  }

void _enterBackground() {
  _appIsBackgrounded = true;
  _backgroundResumeAllowed = _backgroundAudioEnabled &&
      ref.read(playerProvider).isPlaying &&
      !_userPausedInBackground;
  final playing = ref.read(playerProvider).isPlaying;
  if (Platform.isAndroid) {
    // Background audio is a user choice: when it is disabled the app must
    // behave like a plain browser, so leaving it stops the sound (the native
    // foreground service is stopped as a consequence). When enabled, the
    // foreground service + allowBackgroundAudioPlaying keep it playing and the
    // resume logic reasserts playback when returning to the app.
    if (playing && !_backgroundAudioEnabled) {
      MediaControlsService.instance.setPlaying(false);
      ref.read(playerProvider.notifier).pause();
      controlVideo('pause');
      _pushBackgroundAudioToNative();
    }
    return;
  }
  // The iOS-only PiP / audio-session work here is unnecessary on Android
  // (handled by the foreground service + allowBackgroundAudioPlaying), but it
  // is kept so the widget behavior stays in sync with the iOS app if shared.
  _reassertAudioSession();
  if (ref.read(playerProvider).isPlaying) {
    if (_backgroundAudioEnabled) {
      BackgroundAudioKeepAlive.instance.start();
      enterPiP(resumePlayback: true);
    } else {
      BackgroundAudioKeepAlive.instance.stop();
      ref.read(playerProvider.notifier).pause();
      MediaControlsService.instance.setPlaying(false);
      controlVideo('pause');
    }
  }
}

  Future<void> _reassertAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
  }

  // Bumped to force a brand-new InAppWebView after its renderer process died.
  int _browseGen = 0;
  int _videoGen = 0;
  DateTime _lastProcessRecovery = DateTime.fromMillisecondsSinceEpoch(0);

  /// Android kills a WebView's renderer under memory pressure (or on a crash),
  /// leaving a dead view that can't be reused. Registering this handler also
  /// stops the OS from taking the whole app down with it. Recreate the view on
  /// the page we were on. Rate-limited so a page that keeps crashing can't
  /// loop, and skipped in the background (the resume path restores playback).
  void _recoverWebProcess({required bool video}) {
    if (!mounted || _appIsBackgrounded) return;
    final now = DateTime.now();
    if (now.difference(_lastProcessRecovery) < const Duration(seconds: 5)) {
      return;
    }
    _lastProcessRecovery = now;
    debugPrint('[MrPlay] WebView renderer gone (video=$video), recreating');
    setState(() {
      if (video) {
        if (_videoTabUrl == null) return;
        _videoWebViewController = null;
        _pendingVideoUrl = null;
        _videoGen++;
      } else {
        final url = _currentUrl;
        if (url == null || url.startsWith('about:blank')) return;
        _webViewController = null;
        _pendingUrl = url;
        _isLoading = true;
        _loadError = null;
        _browseGen++;
      }
    });
    if (video) {
      Future<void>.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) controlVideo('play');
      });
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

  /// YouTube Music plays inline in the browse webview (single tab). Only
  /// regular YouTube watch pages are routed into the dedicated video tab.
  bool _isMusicUrl(String? url) =>
      url != null && url.contains('music.youtube.com');

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    _currentUrl = url?.toString();
    // The browse tab now holds a page: the platform (not the hub) is on
    // screen, so the floating banner may float over it.
    if (_currentUrl != null && !_currentUrl!.startsWith('about:blank')) {
      layerVisible.value = true;
    }
    if (mounted) setState(() => _isLoading = true);
    if (_loadError != null && mounted) setState(() => _loadError = null);
    _errorController = null;
    _loadingTimer?.cancel();
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _onLoadStop(
      InAppWebViewController controller, WebUri? url) async {
    _loadingTimer?.cancel();
    _platformLoadingTimeout?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _platformLoading = false;
      });
    }
    final urlStr = url?.toString() ?? '';
    if (urlStr.contains('youtube.com') && urlStr.contains('/watch')) {
      if (_isMusicUrl(urlStr)) {
        // YouTube Music: keep the watch page in this (browse) tab.
        _handleWatchPage(controller, urlStr);
      } else if (_videoTabUrl != null && _videoTabUrl == urlStr) {
        _handleWatchPage(controller, urlStr);
      } else {
        _openVideoTab(urlStr);
      }
      if (_unmuteNextLoad) {
        _unmuteNextLoad = false;
        _startUnmuteRetries();
      }
      return;
    }
    _handleWatchPage(controller, urlStr);
    if (_unmuteNextLoad) {
      _unmuteNextLoad = false;
      _startUnmuteRetries();
    }
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
    if (urlStr.contains('youtube.com') &&
        urlStr.contains('/watch') &&
        !_isMusicUrl(urlStr)) {
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
        } catch (_) {}
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
    if (urlStr.contains('youtube.com') &&
        urlStr.contains('/watch') &&
        !_isMusicUrl(urlStr)) {
      if (urlStr != _videoTabUrl) _openVideoTab(urlStr);
    }
  }

  /// Runs the watch-page title extraction (for the mini player). Safe to call
  /// repeatedly for the same page: playerInfo is deduped by video id.
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
        if (video.id.isNotEmpty && currentId != video.id) {
          _endedHandled = false;
          _userPausedInBackground = false;
          _pipRequestedByUser = false;
          _lastReportedPip = false;
          // New video: allow the force-unmute to run again for it.
          _unmuteDone = false;
          if (_videoTabUrl != null) {
            ref.read(playerProvider.notifier).openVideoTab(video);
          } else {
            ref.read(playerProvider.notifier).play(video);
          }
          // YouTube Music: track playback (notification, background audio,
          // stats) but keep the native YTM player as the only visible UI.
          ref.read(playerProvider.notifier)
              .setHidePlayerUi(_isMusicUrl(video.videoUrl));
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
    } catch (_) {}
  }

  void _onVideoState(Map<String, dynamic> data) {
    try {
      final playing = data['playing'] == true;
      final ended = data['ended'] == true;
      final pip = data['pip'] == true;
      final pipStuck = data['pipStuck'] == true;
      _lastReportedPip = pip;
      // Stuck-PiP rescue: iOS leaves webkitPresentationMode == 'picture-in-picture'
      // after the PiP window is dismissed, rendering the in-page video black.
      // Only rescue genuinely stuck mode — NOT when the user just requested PiP.
      // On iOS, pipStuck is always true when in PiP mode (pictureInPictureElement
      // doesn't exist), so we must respect _pipRequestedByUser.
      if (pipStuck && !_appIsBackgrounded && !_pipRequestedByUser) {
        ensureVideoVisible();
      } else if (pip && !_pipRequestedByUser && !_appIsBackgrounded) {
        ensureVideoVisible();
      }
      // When the video exits PiP mode entirely (pip goes from true to false),
      // the PiP window was dismissed. Clear the user-requested flag.
      if (!pip && _pipRequestedByUser) {
        _pipRequestedByUser = false;
      }
      // YouTube starts some videos muted (or the user previously muted it);
      // once the video is actually playing, force-unmute it so audio is
      // audible. Runs once per video.
      if (playing && !ended && !_unmuteDone) {
        _unmuteDone = true;
        _unmuteVideo();
      }
      // Live streams can report non-finite position/duration - clamp to 0 so
      // Duration(milliseconds:) never receives Infinity/NaN (which throws).
      final posSec = (data['position'] as num?)?.toDouble() ?? 0;
      final durSec = (data['duration'] as num?)?.toDouble() ?? 0;
      final positionMs = posSec.isFinite ? posSec * 1000 : 0.0;
      final durationMs = durSec.isFinite ? durSec * 1000 : 0.0;
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
      if (playing && !ended) {
        BackgroundAudioKeepAlive.instance.start();
        _userPausedInBackground = false;
      } else if (!_appIsBackgrounded) {
        // While the app is backgrounded, iOS may pause the webview video
        // momentarily (before/around PiP takeover). Don't kill the keep-alive
        // loop then, or the app gets suspended and audio stops.
        BackgroundAudioKeepAlive.instance.stop();
        if (ended) {
          PlaybackStatsService.instance.flush();
          final id = video?.id ?? '';
          if (id.isNotEmpty) PlaybackStatsService.instance.clearProgress(id);
          _handleEnded();
        }
      } else if (!ended && _backgroundResumeAllowed && data['pip'] != true) {
        // Backgrounded / screen locked and iOS force-paused the webview video
        // (PiP could not take over, e.g. on the lock screen). Resume it so the
        // audio keeps playing; the keep-alive loop holds the process alive and
        // the .playback audio session carries the sound. A pause reported
        // while in PiP is the user pressing the PiP window's pause button -
        // that one must not be resumed.
        controlVideo('play');
      }
    } catch (_) {}
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
    // YouTube Music: track (notification/background/stats) but never render
    // our mini/full player — the native YTM player is the only UI.
    ref.read(playerProvider.notifier).setHidePlayerUi(_isMusicUrl(url));
    MediaControlsService.instance.updateNowPlaying(
      title: video.title,
      artist: video.platform.isEmpty ? 'Web' : video.platform,
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: true,
      artworkUrl: video.thumbnailUrl,
    );
    _userPausedInBackground = false;
    _pipRequestedByUser = false;
    _lastReportedPip = false;
    _unmuteDone = false;
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
    // Throttle position-only updates to ~1s, but push a play/pause change
    // immediately: otherwise the notification stays on the "pause" icon and
    // keeps advancing the timer while the media is actually paused.
    final playingChanged = playing != _lastReportedPlaying;
    // abs(): after seeking backwards / a replay the position drops below the
    // last reported one, which would otherwise freeze the notification time.
    if ((positionMs - _lastNowPlayingMs).abs() < 1000 && !playingChanged) return;
    _lastNowPlayingMs = positionMs;
    _lastReportedPlaying = playing;
    MediaControlsService.instance.updateProgress(
      position: Duration(milliseconds: positionMs),
      duration: Duration(milliseconds: durationMs),
      isPlaying: playing,
    );
  }

  /// URLs already played this session, used to step back through the playback
  /// queue / playlist.
  final List<String> _backStack = [];

  /// Records a URL as the "previous" track for the back-stack.
  void _pushBack(String url) {
    if (url.isEmpty) return;
    if (_backStack.isNotEmpty && _backStack.last == url) return;
    _backStack.add(url);
  }

  /// Steps the queue: removes the current head and loads the next item, or
  /// falls back to the in-page "next" button when the queue is exhausted.
  Future<void> _skipForward() async {
    final items = await QueueRepository.getAll();
    if (items.length > 1) {
      final current = items.first;
      _pushBack(current.platformUrl);
      await QueueRepository.remove(current.id);
      final remaining = await QueueRepository.getAll();
      if (remaining.isNotEmpty && mounted) {
        _endedHandled = false;
        loadUrl(remaining.first.platformUrl);
        return;
      }
    }
    _unmuteNextLoad = true;
    controlVideo('next');
  }

  /// Steps back through played URLs if any, else falls back to the in-page
  /// "previous" button.
  void _skipBackward() {
    if (_backStack.isNotEmpty) {
      final prev = _backStack.removeLast();
      if (mounted && prev.isNotEmpty) {
        _endedHandled = false;
        loadUrl(prev);
        return;
      }
    }
    _unmuteNextLoad = true;
    controlVideo('prev');
  }

  Future<void> _handleEnded() async {
    if (_endedHandled) return;
    _endedHandled = true;
    final items = await QueueRepository.getAll();
    if (items.isEmpty) return;
    final next = items.first;
    _pushBack(next.platformUrl);
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
        _backgroundResumeAllowed = true;
        _userPausedInBackground = false;
        notifier.resume();
        _lastReportedPlaying = true;
        MediaControlsService.instance.setPlaying(true);
        controlVideo('play');
        break;
      case 'pause':
        userInitiatedPause();
        break;
      case 'toggle':
        if (state.isPlaying) {
          userInitiatedPause();
        } else {
          _backgroundResumeAllowed = true;
          _userPausedInBackground = false;
          notifier.resume();
          _lastReportedPlaying = true;
          MediaControlsService.instance.setPlaying(true);
          controlVideo('play');
        }
        break;
      case 'skipForward':
        // Next video: play the next queued playlist item (if any), else
        // trigger the in-page "next" button (playlist / queue).
        _skipForward();
        break;
      case 'skipBackward':
        _skipBackward();
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
  /// to keep audio playing; user pauses must not be fought.
  void userInitiatedPause() {
    _backgroundResumeAllowed = false;
    if (_appIsBackgrounded) _userPausedInBackground = true;
    ref.read(playerProvider.notifier).pause();
    _lastReportedPlaying = false;
    MediaControlsService.instance.setPlaying(false);
    controlVideo('pause');
  }

  /// Shows the mini player: tracks the currently-playing video if needed (so
  /// there is something to display) and collapses the full player. Bound to
  /// the mini-player overlay button in the webview.
  void showMiniPlayer() {
    _userPausedInBackground = false;
    _trackVideoFromUrl();
    if (ref.read(playerProvider).currentVideo != null) {
      ref.read(playerProvider.notifier).minimize();
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
                      icon: Icons.playlist_add,
                      label: 'Add to Playlist',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (video == null) return;
                        final current = video;
                        Future.delayed(const Duration(milliseconds: 300), () {
                          if (mounted) {
                            showAddToPlaylistSheet(context, current);
                          }
                        });
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
                              settings:
                                  const RouteSettings(name: 'Favorites'),
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
                              settings: const RouteSettings(name: 'Settings'),
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

  /// Full cleanup: pauses the video, cancels timers, stops audio keep-alive,
  /// clears now-playing, flushes stats, and dismisses the player state. When a
  /// video tab is open it is closed too, so playback fully stops.
  void closePlayer() {
    controlVideo('pause');
    stopVideoAlignmentWatchdog();
    _stopStatePoll();
    _loadingTimer?.cancel();
    _loadingTimer = null;
    _nowPlayingThrottle?.cancel();
    _nowPlayingThrottle = null;
    _videoTabUrl = null;
    _videoWebViewController = null;
    _pendingVideoUrl = null;
    _tabSwipeOffset = 0;
    _errorController = null;
    BackgroundAudioKeepAlive.instance.stop();
    PlaybackStatsService.instance.flush();
    MediaControlsService.instance.clearNowPlaying();
    ref.read(playerProvider.notifier).dismiss();
    if (mounted) {
      setState(() {
        _loadError = null;
        _isLoading = false;
      });
    }
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
              if (!document.fullscreenElement) v.requestFullscreen().catch(function(){});
            } else if (v.webkitEnterFullscreen) {
              v.webkitEnterFullscreen();
            }
          })();
        ''');
        break;
      case 'exitFullscreen':
        controller.evaluateJavascript(source: '''
          (function() {
            if (document.fullscreenElement) {
              document.exitFullscreen().catch(function(){});
            }
          })();
        ''');
        break;
      case 'next':
        controller.evaluateJavascript(source: r'''
          (function() {
            var host = location.hostname;
            var isMusic = host.indexOf('music.') !== -1;
            var isYt = host.indexOf('youtube.com') !== -1 || host.indexOf('youtu.be') !== -1;

            var currentV = null;
            try { currentV = new URL(location.href).searchParams.get('v'); } catch (e) {}

            // A link is the current video ONLY when its video id matches the one
            // playing. Comparing raw hrefs misfires when the current URL carries
            // playlist/queue params that the link omits (or vice-versa), which
            // made "next" silently reload the same video.
            function isSameVideo(link) {
              if (currentV == null) return false;
              try {
                var v = new URL(link.href).searchParams.get('v');
                return v != null && v === currentV;
              } catch (e) { return false; }
            }

            function firstNextLink(root) {
              var links = (root || document).querySelectorAll('a[href*="/watch?v="]');
              for (var i = 0; i < links.length; i++) {
                if (isSameVideo(links[i])) continue;
                return links[i];
              }
              return null;
            }

            function clickNextButton() {
              var btn = document.querySelector(
                  '.ytp-next-button, a.ytp-next-button, #next-button, ' +
                  'ytmusic-player-bar #next-button, tp-yt-paper-icon-button.next-button, ' +
                  'ytmusic-player-bar [aria-label="Next"]');
              if (!btn) return false;
              try { btn.click(); return true; } catch (e) { return false; }
            }

            // YouTube Music: the queue-aware "Next" lives in the player bar
            // (often behind a shadow root), so it wins over related links.
            if (isMusic) {
              if (clickNextButton()) return;
              var stack = [document];
              var guard = 0;
              while (stack.length && guard < 20000) {
                var root = stack.pop();
                var all = root.querySelectorAll('*');
                for (var j = 0; j < all.length; j++) {
                  if (++guard > 20000) break;
                  var node = all[j];
                  var nid = node.id || '';
                  var cls = (node.getAttribute && node.getAttribute('class')) || '';
                  var lbl = (node.getAttribute && node.getAttribute('aria-label')) || '';
                  if (nid === 'next-button' || cls.indexOf('next-button') !== -1 ||
                      lbl.toLowerCase() === 'next') {
                    node.click();
                    return;
                  }
                  if (node.shadowRoot) stack.push(node.shadowRoot);
                }
              }
              return;
            }

            // Regular YouTube: prefer the Up-next / related-video links. Clicking
            // the anchor keeps YouTube's in-page (SPA) history, so "previous" can
            // walk back through the videos. The generic [aria-label="Next"]
            // catch-all is intentionally dropped: on mobile layouts it matches
            // unrelated junk and returns early without doing anything.
            if (isYt) {
              var scopes = [
                document.querySelector('ytd-playlist-panel-renderer'),
                document.querySelector('#related ytd-compact-autoplay-renderer'),
                document.querySelector('#secondary ytd-compact-autoplay-renderer'),
                document.querySelector('#related'),
                document.querySelector('#secondary'),
                document
              ];
              for (var s = 0; s < scopes.length; s++) {
                var a = firstNextLink(scopes[s]);
                if (!a) continue;
                try { sessionStorage.setItem('__mrplay_unmute', '1'); } catch (e) {}
                a.click();
                return;
              }
            }
            clickNextButton();
          })();
        ''');
        break;
      case 'prev':
        controller.evaluateJavascript(source: r'''
          (function() {
            var host = location.hostname;
            var isMusic = host.indexOf('music.') !== -1;
            var isYt = host.indexOf('youtube.com') !== -1 || host.indexOf('youtu.be') !== -1;

            var btn = document.querySelector(
                '.ytp-prev-button, a.ytp-prev-button, #previous-button, ' +
                'ytmusic-player-bar #previous-button, tp-yt-paper-icon-button.previous-button, ' +
                'ytmusic-player-bar [aria-label="Previous"]');
            if (btn) { try { btn.click(); return; } catch (e) {} }

            if (isMusic) {
              var stack = [document];
              var guard = 0;
              while (stack.length && guard < 20000) {
                var root = stack.pop();
                var all = root.querySelectorAll('*');
                for (var j = 0; j < all.length; j++) {
                  if (++guard > 20000) break;
                  var node = all[j];
                  var nid = node.id || '';
                  var cls = (node.getAttribute && node.getAttribute('class')) || '';
                  var lbl = (node.getAttribute && node.getAttribute('aria-label')) || '';
                  if (nid === 'previous-button' || cls.indexOf('previous-button') !== -1 ||
                      lbl.toLowerCase() === 'previous') {
                    node.click();
                    return;
                  }
                  if (node.shadowRoot) stack.push(node.shadowRoot);
                }
              }
              return;
            }
            // YouTube (non-Music): the mobile player has no previous button,
            // so step back through the SPA navigation history (previous video).
            if (isYt && location.href.indexOf('/watch') !== -1 && window.history.length > 1) {
              try { sessionStorage.setItem('__mrplay_unmute', '1'); } catch (e) {}
              window.history.back();
            }
          })();
        ''');
        break;
    }
  }

  /// Un-mutes the actively playing video. YouTube sometimes starts playback
  /// muted (or the user previously muted it), and the "tap to unmute" overlay
  /// needs a tap. We bypass the UI by directly clearing `muted` on the video
  /// element(s) and restoring volume, once per video.
  void _unmuteVideo() {
    _activeController?.evaluateJavascript(source: '''
      (function() {
        var videos = document.querySelectorAll('video');
        for (var i = 0; i < videos.length; i++) {
          var v = videos[i];
          if (v.muted || v.volume === 0) {
            v.muted = false;
            v.defaultMuted = false;
            v.volume = 1;
          }
        }
      })();
    ''');
  }

  /// YouTube autoplays a programmatically-navigated video muted (no user
  /// gesture). Retry unmuting for a few seconds so it catches the video even
  /// though YouTube applies the mute after the page finishes loading.
  void _startUnmuteRetries() {
    _unmuteTimer?.cancel();
    var attempts = 0;
    _unmuteTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      attempts++;
      if (!mounted || attempts > 8) {
        timer.cancel();
        _unmuteTimer = null;
        return;
      }
      _activeController?.evaluateJavascript(source: '''
        (function() {
          var v = document.querySelector('#movie_player video') || document.querySelector('video');
          if (!v) return;
          if (v.muted) {
            var btn = document.querySelector('.ytp-mute-button');
            if (btn) { try { btn.click(); } catch (e) {} }
            v.muted = false;
            if (v.volume === 0) v.volume = 1;
          }
        })();
      ''');
    });
  }

  /// Routes YouTube /watch links into the dedicated video tab; everything else
  /// loads in the browse webview. YouTube Music never uses the video tab: its
  /// watch pages play inline in the browse webview (single tab).
  void loadUrl(String url) {
    if (url.contains('youtube.com') &&
        url.contains('/watch') &&
        !_isMusicUrl(url)) {
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
      _platformLoading = true;
      _loadError = null;
    });
    _endedHandled = false;
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isLoading = false);
    });
    // Safety net: some SPA platforms never fire onLoadStop, so don't leave the
    // full-screen loader up forever.
    _platformLoadingTimeout?.cancel();
    _platformLoadingTimeout = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _platformLoading = false);
    });
  }

  /// Opens (or re-slots) the dedicated video tab onto the given watch URL.
  /// If the tab webview already exists it simply navigates (reloading the new
  /// video); otherwise the URL is stashed and consumed when the tab widget is
  /// built. The tab is expanded and fades in from the bottom so a new video
  /// selected on the browse tab visibly pops the second tab back up.
  void _openVideoTab(String url) {
    final sameTab = _videoTabUrl == url;
    _videoTabUrl = url;
    if (!sameTab) {
      _endedHandled = false;
      _unmuteDone = false;
      _videoTabIntro = true;
    }
    ref.read(playerProvider.notifier).videoTabActive();
    final vc = _videoWebViewController;
    if (vc != null) {
      if (!sameTab) {
        vc.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      }
    } else {
      _pendingVideoUrl = url;
    }
    if (mounted) {
      setState(() {
        // The webview layer self-hides until ready. A watch URL opened from
        // outside (bookmarks / deep link / widget) can arrive while it is
        // still hidden (e.g. from the hub) — bring it up or the tab has no
        // surface to render on.
        isReady = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _videoTabIntro) setState(() => _videoTabIntro = false);
      });
    }
  }

  void _onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (request.isForMainFrame == true) {
      if (mounted) {
        _errorController = controller;
        setState(() {
          _platformLoading = false;
          _loadError = 'Could not load the page: ${error.description}';
        });
      }
    }
  }

  void _onReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse response,
  ) {
    if (request.isForMainFrame == true) {
      if (mounted) {
        _errorController = controller;
        setState(() {
          _platformLoading = false;
          _loadError = 'Server error ${response.statusCode ?? 'unknown'}';
        });
      }
    }
  }

  void _retryLoad() {
    if (!mounted) return;
    setState(() => _loadError = null);
    final controller = _errorController ?? _webViewController;
    _errorController = null;
    controller?.reload();
  }

  void enterPiP({bool resumePlayback = false}) {
    // Android WebView has no HTML5 PiP API: use the native activity PiP
    // overlay. The video keeps playing inside the scaled-down webview.
    if (Platform.isAndroid) {
      PictureInPictureService.instance.enter();
      return;
    }
    _pipRequestedByUser = true;
    _activeController?.evaluateJavascript(source: '''
      (function() {
        var video = $_activeVideoJs;
        if (!video) return;
        if (video.requestPictureInPicture) {
          if (document.pictureInPictureElement) return;
          video.requestPictureInPicture().catch(function(){});
        } else if (video.webkitSetPresentationMode) {
          if (video.webkitPresentationMode !== 'picture-in-picture') {
            video.webkitSetPresentationMode('picture-in-picture');
          }
        }
        if ($resumePlayback) {
          if (video.paused) {
            video.play().catch(function() {
              var btn = document.querySelector('.ytp-play-button');
              if (btn) btn.click();
            });
          }
        }
      })();
    ''');
  }

  /// Brings the playing <video> back inline after auto-PiP on backgrounding.
  /// Without this, returning to the app leaves the in-page player black while
  /// the video keeps floating in the PiP window.
  void exitPiP() {
    if (Platform.isAndroid) {
      PictureInPictureService.instance.exit();
      return;
    }
    _pipRequestedByUser = false;
    _lastReportedPip = false;
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

  /// Last-resort fallback: if exitPiP failed to bring the video back inline,
  /// force the video element to be visible so the user doesn't see a black
  /// screen. Tries webkitSetPresentationMode('inline'), then falls back to a
  /// DOM reinsertion trick — removing the <video> from the DOM and putting it
  /// back forces iOS to reset the presentation pipeline, which is more
  /// reliable than the API call (which iOS can silently ignore).
  void ensureVideoVisible() {
    // iOS-only PiP un-stick fix (heavy DOM manipulation). Android has no stuck
    // PiP mode, so skip it and avoid the repeated evaluateJavascript churn.
    if (Platform.isAndroid) return;
    _pipRequestedByUser = false;
    _lastReportedPip = false;
    _activeController?.evaluateJavascript(source: '''
      (function() {
        var video = document.querySelector('video');
        if (!video) return;
        try {
          if (video.webkitSetPresentationMode &&
              video.webkitPresentationMode === 'picture-in-picture') {
            video.webkitSetPresentationMode('inline');
          }
        } catch (e) {}
        video.style.setProperty('visibility', 'visible', 'important');
        video.style.setProperty('opacity', '1', 'important');
        video.style.removeProperty('display');
        video.style.removeProperty('clip');
        video.style.removeProperty('clip-path');
        video.style.removeProperty('width');
        video.style.removeProperty('height');
        video.style.setProperty('object-fit', 'contain', 'important');
        var player = document.querySelector('#movie_player');
        if (player) {
          var pipPlaceholder = player.querySelector('.ytp-pip-container, [class*="pip"]');
          if (pipPlaceholder) pipPlaceholder.remove();
          var poster = player.querySelector('.ytp-cued-thumbnail-overlay, .ytp-poster, .ytp-cued-thumbnail-overlay-image, [class*="thumbnail"][class*="overlay"]');
          if (poster) poster.style.display = 'none';
        }
        // Scroll the video into the viewport in case the player layout
        // was broken (e.g. by the old #movie_player position override).
        var r = video.getBoundingClientRect();
        if (r.height < 10 || r.width < 10 || r.top < -window.innerHeight) {
          var c = player || video.parentElement;
          if (c) {
            var cr = c.getBoundingClientRect();
            var t = window.scrollY + cr.top - 50;
            if (t < 0) t = 0;
            window.scrollTo({top: t, behavior: 'instant'});
          }
        }
        // DOM reinsertion trick: if the video is still stuck in PiP mode after
        // the API call above, briefly remove it from the DOM and reinsert it.
        // This forces iOS WKWebView to tear down and rebuild the presentation
        // pipeline — the only reliable way to escape a stuck presentation mode.
        if (video.webkitPresentationMode === 'picture-in-picture') {
          var parent = video.parentNode;
          if (parent) {
            var wasPlaying = !video.paused;
            var next = video.nextSibling;
            var currentTime = video.currentTime;
            parent.removeChild(video);
            parent.insertBefore(video, next);
            video.currentTime = currentTime;
            if (wasPlaying) {
              video.play().catch(function(){});
            }
          }
        }
      })();
    ''');
  }

  void startVideoAlignmentWatchdog() {
    if (Platform.isAndroid) return;
    _alignmentWatchdog?.cancel();
    var ticks = 0;
    _alignmentWatchdog = Timer.periodic(const Duration(milliseconds: 400), (t) {
      ensureVideoVisible();
      ticks++;
      if (ticks >= 8) t.cancel();
    });
  }

  void stopVideoAlignmentWatchdog() {
    _alignmentWatchdog?.cancel();
    _alignmentWatchdog = null;
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

  /// Whether the Dart-side state poll should be running. It's only needed while
  /// the full player is expanded and visible (the webview is occluded, so iOS
  /// throttles the page's own heartbeat). The mini player, YouTube Music
  /// (hidePlayerUi) and the PiP overlay rely on the page-side heartbeat instead.
  bool _shouldPoll(PlayerState? s) {
    if (s == null || s.currentVideo == null) return false;
    return !s.isMinimized && !s.isInPip && !s.hidePlayerUi;
  }

  Future<void> _pollVideoState() async {
    // Skip the Dart-side poll while the PiP overlay is showing: the page's own
    // videoState heartbeat still reports position/duration for the media
    // notification, and dropping the poll avoids paying for evaluateJavascript
    // round-trips + provider rebuilds every 500ms inside the PiP window (the
    // source of the laggy playback).
    if (PictureInPictureService.instance.isInPip.value) return;
    final controller = _activeController;
    if (_statePoll == null || controller == null) return;
    if (_pollInFlight) return;
    _pollInFlight = true;
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
    } catch (_) {
    } finally {
      _pollInFlight = false;
    }
  }

  /// Forces the video back inline when the full player collapses to the mini
  /// player, unless PiP is actively showing (user sees a PiP window). Covers
  /// the stuck-PiP case where the black in-page video only becomes visible
  /// again in the PiP window.
  void _unstickPiPIfUnrequested() {
    if (Platform.isAndroid) return;
    if (_appIsBackgrounded) return;
    if (_pipRequestedByUser) return;
    ensureVideoVisible();
    // iOS can leave the video stuck in PiP presentation mode even after the
    // first un-stick attempt; re-check once shortly after so the in-page video
    // doesn't stay black when the webview reappears.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && !_pipRequestedByUser) ensureVideoVisible();
    });
  }

  /// Reacts to the native Android PiP overlay opening/closing: mirrors it into
  /// the player state (so the shell/overlays can hide) and toggles a bit of
  /// page CSS so the floating window shows mostly the video instead of the
  /// whole comment thread.
  void _onPipModeChanged() {
    final inPip = PictureInPictureService.instance.isInPip.value;
    ref.read(playerProvider.notifier).setPipMode(inPip);
    if (inPip) {
      _pipRequestedByUser = true;
      _lastReportedPip = true;
      _hidePageClutter();
    } else {
      _pipRequestedByUser = false;
      _lastReportedPip = false;
      _showPageClutter();
    }
    if (mounted) setState(() {});
  }

  void _hidePageClutter() {
    _videoWebViewController?.evaluateJavascript(
      source: VideoTabJS.pipClutterHideScript,
    );
  }

  void _showPageClutter() {
    _videoWebViewController?.evaluateJavascript(
      source: VideoTabJS.pipClutterRestoreScript,
    );
  }

  void togglePictureInPicture() {
    if (Platform.isAndroid) {
      if (PictureInPictureService.instance.isInPip.value) {
        PictureInPictureService.instance.exit();
      } else {
        PictureInPictureService.instance.enter();
      }
      return;
    }
    _pipRequestedByUser = !_lastReportedPip;
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

  @override
  Widget build(BuildContext context) {
    ref.listen(playerProvider, (prev, next) {
      final collapsedToMini = prev?.isMinimized == false && next.isMinimized;
      if (collapsedToMini) _unstickPiPIfUnrequested();
      // The Dart-side poll is only needed while the full player is expanded and
      // occludes the webview (iOS throttles the page's own heartbeat then).
      // Collapsed to the mini player, hidden (YouTube Music) or in PiP, the
      // page's own videoState heartbeat is sufficient — pause the poll so we
      // don't pay for an evaluateJavascript round-trip every 500ms.
      final prevPoll = _shouldPoll(prev);
      final nextPoll = _shouldPoll(next);
      if (nextPoll && !prevPoll) {
        _startStatePoll();
      } else if (!nextPoll && prevPoll) {
        _stopStatePoll();
      }
    });
    if (!isReady) return const SizedBox.shrink();

    final playerState = ref.watch(playerProvider);
    final videoTabCollapsed = _videoTabUrl != null &&
        playerState.isVideoTab &&
        playerState.isMinimized;
    // While the collapsed video tab is showing its mini bar (which floats at
    // bottomNav 52 + bottom inset, 64 tall) the floating side buttons must sit
    // just above it instead of overlapping it. When the tab is expanded there
    // is no mini bar, so the buttons keep their lower positions.
    final double sideBtnBase = videoTabCollapsed
        ? MediaQuery.of(context).padding.bottom + 52 + 64 + 8
        : 80;
    // While the system PiP overlay is showing, hide all Flutter chrome so the
    // floating window contains just the webview (the video).
    final inPip = playerState.isInPip;

    return Stack(
      children: [
        // While the PiP overlay is showing, don't paint the browse WebView:
        // only the video tab's texture should be composited into the scaled
        // PiP window (two full-res textures downscaled is what made playback
        // janky). The webview keeps its state (Offstage, not disposed).
        //
        // The browse tab also stays offstage until it actually holds a page
        // (_currentUrl). Playing a saved/history video from an overlay page
        // routes straight into the video tab without ever navigating the
        // browse webview — keeping it offstage then lets the hub below show
        // through, so collapsing the mini player lands back on the hub.
        // When playback started inside a platform the browse webview has its
        // page and collapsing reveals that platform instead.
        Offstage(
          offstage: inPip || _currentUrl == null,
          child: SizedBox.expand(
            child: InAppWebView(
              key: ValueKey('browse-tab-$_browseGen'),
              initialUserScripts: UnmodifiableListView([
                if (_adBlockEnabled) ...[
                  UserScript(
                    source: ContentBlockerJS.playerAdsStripperScript,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    groupName: _adBlockScriptGroup,
                  ),
                  UserScript(
                    source: ContentBlockerJS.adRequestBlockerScript,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    groupName: _adBlockScriptGroup,
                  ),
                  UserScript(
                    source: ContentBlockerJS.genericAdBlockerScript,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    groupName: _adBlockScriptGroup,
                  ),
                  UserScript(
                    source: ContentBlockerJS.adFallbackSkipScript,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    groupName: _adBlockScriptGroup,
                  ),
                ],
                UserScript(
                  source: YouTubeJS.visibilityKeepAliveScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
                UserScript(
                  source: YouTubeJS.appBannerRemoverScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
                UserScript(
                  source: YouTubeJS.unmutePopupRemoverScript,
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
                // Texture-layer rendering (instead of the VirtualDisplay used by
                // hybrid composition). Required on Android so the WebView stays in
                // the activity window and `allowBackgroundAudioPlaying` actually
                // fires on backgrounding (in hybrid composition the WebView lives
                // in a VirtualDisplay whose visibility never changes). Also lets
                // Flutter draw the full/mini player over the WebView.
                useHybridComposition: false,
                userAgent: _userAgent(),
              ),
              onWebViewCreated: _onWebViewCreated,
              onLoadStart: _onLoadStart,
              onLoadStop: _onLoadStop,
              onUpdateVisitedHistory: _onBrowseVisitedHistory,
              onReceivedError: _onReceivedError,
              onReceivedHttpError: _onReceivedHttpError,
              onRenderProcessGone: (controller, detail) =>
                  _recoverWebProcess(video: false),
              shouldInterceptRequest: (controller, request) async {
                if (!_adBlockEnabled) return null;
                return WebViewAdBlocker.intercept(request);
              },
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
                  // Block everything else (youtube://, vnd.youtube://, intent://,
                  // javascript:, data:, blob:, ...) so "Open in app" links stay
                  // inside MrPlay instead of bouncing to an external app.
                }
                return NavigationActionPolicy.CANCEL;
              },
              onCreateWindow: (controller, createWindowAction) async {
                // Open popup/new-window targets (e.g. OAuth "Continue with ...")
                // inside the main WebView instead of dropping them.
                final url = createWindowAction.request.url;
                if (url != null) {
                  controller.loadUrl(urlRequest: URLRequest(url: url));
                }
                return false;
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
                      : (videoTabCollapsed
                          ? const Offset(0, 0.25)
                          : Offset.zero),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: InAppWebView(
                    key: ValueKey('video-tab-$_videoGen'),
                    initialUrlRequest: URLRequest(url: WebUri(_videoTabUrl!)),
                    initialUserScripts: UnmodifiableListView([
                      UserScript(
                        source: VideoTabJS.headerRemoverScript,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      UserScript(
                        source: VideoTabJS.swipeCollapseScript,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      if (_adBlockEnabled) ...[
                        UserScript(
                          source: ContentBlockerJS.playerAdsStripperScript,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                          groupName: _adBlockScriptGroup,
                        ),
                        UserScript(
                          source: ContentBlockerJS.adRequestBlockerScript,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                          groupName: _adBlockScriptGroup,
                        ),
                        UserScript(
                          source: ContentBlockerJS.genericAdBlockerScript,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                          groupName: _adBlockScriptGroup,
                        ),
                        UserScript(
                          source: ContentBlockerJS.adFallbackSkipScript,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                          groupName: _adBlockScriptGroup,
                        ),
                      ],
                      UserScript(
                        source: YouTubeJS.visibilityKeepAliveScript,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      UserScript(
                        source: YouTubeJS.appBannerRemoverScript,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      UserScript(
                        source: YouTubeJS.unmutePopupRemoverScript,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      UserScript(
                        source: YouTubeJS.playerControlsScript,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                      UserScript(
                        source: MediaObserverJS.genericObserverScript,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
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
                      useHybridComposition: false,
                      userAgent: _userAgent(),
                    ),
                    onWebViewCreated: _onVideoWebViewCreated,
                    onLoadStart: _onVideoLoadStart,
                    onLoadStop: _onLoadStop,
                    onUpdateVisitedHistory: _onVideoVisitedHistory,
                    onReceivedError: _onReceivedError,
                    onReceivedHttpError: _onReceivedHttpError,
                    onRenderProcessGone: (controller, detail) =>
                        _recoverWebProcess(video: true),
                    shouldInterceptRequest: (controller, request) async {
                      if (!_adBlockEnabled) return null;
                      return WebViewAdBlocker.intercept(request);
                    },
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
                      }
                      return NavigationActionPolicy.CANCEL;
                    },
                    onCreateWindow: (controller, createWindowAction) async {
                      final url = createWindowAction.request.url;
                      if (url != null) {
                        controller.loadUrl(urlRequest: URLRequest(url: url));
                      }
                      return false;
                    },
                  ),
                ),
              ),
            ),
          ),
        if (_loadError != null && !_isLoading && !inPip)
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: CustomErrorWidget(
                message: _loadError!,
                onRetry: _retryLoad,
              ),
            ),
          ),
        if (_platformLoading && _loadError == null && !inPip)
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.red,
                      strokeWidth: 3,
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: _goToHub,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_isLoading && !_platformLoading && !inPip)
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
        if (_videoTabUrl != null && !videoTabCollapsed && !inPip)
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
        if (!inPip) ...[
          Positioned(
            bottom: sideBtnBase + 126,
            right: 16,
            child: GestureDetector(
              onTap: _showOptionsModal,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D).withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                ),
                child:
                    const Icon(Icons.more_horiz, color: Colors.white, size: 24),
              ),
            ),
          ),
          Positioned(
            bottom: sideBtnBase + 84,
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
            bottom: sideBtnBase + 42,
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
            bottom: sideBtnBase,
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
      ],
    );
  }

  /// Full reset back to the hub: pauses playback, tears down the video tab
  /// (if any), blanks the browse webview, and hides the whole webview layer so
  /// the HubPage (below in the app Stack) becomes visible again.
  void _goToHub() {
    controlVideo('pause');
    stopVideoAlignmentWatchdog();
    _stopStatePoll();
    _loadingTimer?.cancel();
    _loadingTimer = null;
    _nowPlayingThrottle?.cancel();
    _nowPlayingThrottle = null;
    _videoTabUrl = null;
    _videoWebViewController = null;
    _pendingVideoUrl = null;
    _tabSwipeOffset = 0;
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
    _webViewController = null;
    _currentUrl = null;
    _errorController = null;
    BackgroundAudioKeepAlive.instance.stop();
    PlaybackStatsService.instance.flush();
    MediaControlsService.instance.clearNowPlaying();
    ref.read(playerProvider.notifier).dismiss();
    if (mounted) {
      setState(() {
        isReady = false;
        _isLoading = false;
        _platformLoading = false;
        _loadError = null;
      });
    }
    layerVisible.value = false;
  }

  /// Android system back button. Walks back through the app's layers in a
  /// natural order: collapse the open video tab -> step back within the
  /// platform page (keeps playback) -> return to the hub -> exit the app.
  /// Returns false when the press was not consumed (caller should exit).
  Future<bool> handleBack() async {
    final state = ref.read(playerProvider);

    // A video tab is open.
    if (_videoTabUrl != null) {
      if (!state.isMinimized) {
        // Expanded: collapse it to the mini bar, revealing the platform page.
        _minimizeVideoTab();
      } else {
        // Already collapsed (mini bar): leave playback and return to the hub.
        _goToHub();
      }
      return true;
    }

    // Step back within the current platform page when it has in-page history
    // (e.g. YouTube Music now-playing -> library). Playback keeps going.
    final wvc = _webViewController;
    if (wvc != null) {
      try {
        if (await wvc.canGoBack()) {
          wvc.goBack();
          return true;
        }
      } catch (_) {}
    }

    // A platform is open at its entry page: return to the hub.
    if (layerVisible.value || isReady) {
      _goToHub();
      return true;
    }

    // On the hub already: let the system exit.
    return false;
  }

  void _minimizeVideoTab() {
    if (_videoTabUrl == null) return;
    _tabSwipeOffset = 0;
    ref.read(playerProvider.notifier).minimize();
  }

  void _onTabSwipeUpdate(DragUpdateDetails details) {
    setState(() {
      _tabSwipeOffset += details.delta.dy;
      if (_tabSwipeOffset < 0) _tabSwipeOffset = 0;
    });
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
