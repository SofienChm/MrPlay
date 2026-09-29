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
  DateTime _lastUnmuteAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _unmuteThrottle = Duration(milliseconds: 1200);
  DateTime? _pipStuckSince;
  DateTime _lastInlineForce = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _pipStuckGrace = Duration(milliseconds: 800);
  static const Duration _inlineForceThrottle = Duration(seconds: 3);
  static const String _adBlockScriptGroup = 'mrplay-adblock';
  DateTime _lastPopupAllowedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _popupFloodGap = Duration(milliseconds: 1200);
  Timer? _pausedKeepAliveTimer;
  static const Duration _pausedKeepAliveInterval = Duration(seconds: 4);
  bool _wasPlayingAtSeek = false;
  DateTime _lastSeekDragTick = DateTime.fromMillisecondsSinceEpoch(0);
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
  String? _loadError;
  Timer? _loadingTimer;
  Timer? _nowPlayingThrottle;
  bool _endedHandled = false;
  /// True while the app is backgrounded and the queue just advanced to the
  /// next video, but that video hasn't started playing yet. Used on resume to
  /// auto-start a video the background handoff left stuck on its loader.
  bool _backgroundHandoffPending = false;
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
  Timer? _statePoll;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  /// Timestamp of the last time playback was (re)started by MrPlay, the page,
  /// or a new video. Interruptions that arrive shortly after are almost always
  /// transient session toggling (AdMob SDK / WebKit handoff on the *shared*
  /// AVAudioSession), not a real system interruption, so they are not acted on.
  DateTime _lastPlayInitiatedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// How long after our own play start transient interruptions are ignored.
  static const Duration _interruptionGrace = Duration(milliseconds: 2500);

  /// Last time the `<video>` reported actually playing. Used to tell a
  /// lock-screen / Control Center scrub of a *playing* video apart from a
  /// deliberate pause followed by a scrub: iOS pauses the element during the
  /// drag (so `state.isPlaying` is already false by the time the seek lands)
  /// and never sends a follow-up play command, leaving the element stuck on
  /// the buffering spinner. Cleared on explicit user/system pauses.
  DateTime _lastKnownPlayingAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Debounced timer that resumes playback after a remote seek (see
  /// [_resumeAfterRemoteSeek]). Reset on every seek event so a long scrub drag
  /// only resumes once the user lifts their finger.
  Timer? _remoteSeekResumeTimer;

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

  @visibleForTesting
  static bool isAdDomain(String host) {
    final h = host.toLowerCase();
    // Ad/tracker/redirect networks used by popup-flood sites. Kept to clearly
    // ad-serving domains so legit content platforms (youtube.com, twitch.tv,
    // ...) and googlevideo.com (real video CDN) are never matched.
    const adDomains = [
      'doubleclick.net',
      'googlesyndication.com',
      'googleadservices.com',
      'google-analytics.com',
      'adservice.google.com',
      'pagead2.googlesyndication.com',
      'tpc.googlesyndication.com',
      'amazon-adsystem.com',
      'adnxs.com',
      'adform.net',
      'taboola.com',
      'outbrain.com',
      'pubmatic.com',
      'criteo.com',
      'rubiconproject.com',
      'adsrvr.org',
      'tremorhub.com',
      'springserve.com',
      // Popup / popunder ad networks — the "jump a lot of popups" culprits.
      'popads.net',
      'popcash.net',
      'popunder.net',
      'propellerads.com',
      'adsterra.com',
      'exoclick.com',
      'exosrv.com',
      'juicyads.com',
      'admaven.com',
      'ad-maven.com',
      'mgid.com',
      'revcontent.com',
      'popmyads.com',
      'adscendmedia.com',
      'contextweb.com',
      'openx.net',
      'smartadserver.com',
      'zedo.com',
      'quantserve.com',
      'scorecardresearch.com',
      'casalemedia.com',
      'serving-sys.com',
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

  /// The four ad-blocking user scripts, grouped so they can be added/removed at
  /// runtime when the "Block ads & trackers" toggle is flipped (no app restart).
  List<UserScript> _adBlockScripts() => [
        UserScript(
          source: ContentBlockerJS.stripAdDataScript,
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
      ];

  /// Re-applies the ad-block and background-audio settings without an app
  /// restart, after the user toggles them in Settings. Ad-block scripts are
  /// injected into the live webviews (and applied to the current pages) when
  /// enabled, and removed (for future loads) when disabled. Background audio
  /// only flips the runtime flag: the webviews are always created with PiP and
  /// background-audio capability enabled, so the phantom-PiP keep-alive can
  /// engage on the next background without recreating the webview.
  Future<void> applySettingsChanges() async {
    final adBlock = await SettingsRepository.getAdBlockEnabled();
    final backgroundAudio = await SettingsRepository.getBackgroundAudioEnabled();
    if (adBlock != _adBlockEnabled) {
      _adBlockEnabled = adBlock;
      if (mounted) setState(() {});
      await _applyAdBlockRuntime();
    }
    if (backgroundAudio != _backgroundAudioEnabled) {
      _backgroundAudioEnabled = backgroundAudio;
      if (mounted) setState(() {});
    }
  }

  /// Applies (or removes) the ad-block user scripts on the already-created
  /// webviews. Runtime-added scripts only run on the next document start, so
  /// when enabling we also evaluate each script on the current page.
  Future<void> _applyAdBlockRuntime() async {
    final scripts = [
      ContentBlockerJS.stripAdDataScript,
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

  /// Listens for AVAudioSession interruptions (a phone call, Siri, another app
  /// grabbing the audio session...). The interruptor's `begin` event is not
  /// acted on blindly: the shared AVAudioSession is also touched transiently by
  /// the AdMob SDK and by WebKit's own media handoff on first play, which iOS
  /// misreports as an interruption even though nothing paused our `<video>`.
  /// [_handleAudioInterruptionBegan] verifies against the actual element before
  /// latching a system pause, so those transient events can't kill playback.
  Future<void> _subscribeToAudioInterruptions() async {
    try {
      final session = await AudioSession.instance;
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (!mounted) return;
        if (event.begin) {
          if (ref.read(playerProvider).isPlaying) {
            _handleAudioInterruptionBegan();
          }
        } else if (_systemPaused) {
          // A genuine interruption that latched a system pause just ended.
          // Re-assert the session and, while backgrounded, re-apply the
          // keep-alive so a lock-screen play can still reach the webview
          // (the same "can't resume from notification center" class of bug).
          _handleAudioInterruptionEnded();
        }
      });
    } catch (e) {
      debugPrint('[MrPlay] audio interruption subscribe failed: $e');
    }
  }

  /// Verifies an interruption before pausing. A genuine system interruption
  /// pauses the `<video>` element itself (WebKit is interrupted too), so a
  /// short grace window plus a fresh element poll distinguish it from the
  /// transient session toggling of the ad SDK / WebKit first-play handoff.
  Future<void> _handleAudioInterruptionBegan() async {
    // In the background the webview may already be suspended and can't be
    // polled, so treat every interruption as genuine there (a call / another
    // app seizing the session really does stop our keep-alive audio).
    if (!_appIsBackgrounded) {
      // Ignore interruptions arriving right after we (or the page) started
      // playback - this is when the AdMob SDK / WebKit settle the shared audio
      // session and iOS emits a spurious "interruption began".
      if (DateTime.now().difference(_lastPlayInitiatedAt) < _interruptionGrace) {
        return;
      }
      if (mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      if (!mounted) return;
      await _pollVideoState();
      if (!mounted) return;
      // The element is still playing -> the "interruption" was transient
      // (session toggling), not the system taking our audio. Ignore it.
      if (ref.read(playerProvider).isPlaying) return;
    }
    _systemPause();
  }

  /// A genuine interruption (call / another app seizing the session) that
  /// latched a system pause has ended. Clear the latch, re-assert our session,
  /// and while backgrounded re-apply the keep-alive so a lock-screen play can
  /// still reach the webview — otherwise iOS suspends it and the notification
  /// center play button stops working until the app is reopened.
  Future<void> _handleAudioInterruptionEnded() async {
    _systemPaused = false;
    _systemPausedElapsed = 0;
    _reassertAudioSession();
    if (!_appIsBackgrounded || !_backgroundAudioEnabled) return;
    if (ref.read(playerProvider).isPlaying) {
      if (_isMusic) {
        BackgroundAudioKeepAlive.instance.start();
      } else {
        _enterPhantomPiP();
      }
    } else if (!_userPausedInBackground) {
      // The system paused us and the user hasn't paused on their own: keep the
      // WebView alive so a lock-screen play can reach it.
      BackgroundAudioKeepAlive.instance.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadingTimer?.cancel();
    _nowPlayingThrottle?.cancel();
    _statePoll?.cancel();
    _remoteSeekResumeTimer?.cancel();
    _interruptionSub?.cancel();
    _stopPausedKeepAlive();
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
      final shouldKickStuckVideo = _backgroundHandoffPending &&
          !_systemPaused &&
          !_userPausedInBackground &&
          _backgroundAudioEnabled;
      _appIsBackgrounded = false;
      _userPausedInBackground = false;
      _backgroundHandoffPending = false;
      _stopPausedKeepAlive();
      // Stop the keep-alive when the app is back in the foreground and the
      // video is not playing (the silent loop is no longer needed). For a
      // regular video, drop the loop even while playing: in the foreground the
      // visible player / phantom-PiP restore holds the audio session.
      if (!ref.read(playerProvider).isPlaying && !_systemPaused) {
        BackgroundAudioKeepAlive.instance.stop();
      } else if (!_isMusic) {
        BackgroundAudioKeepAlive.instance.stop();
      }
      // The video was phantom-PiP'd on background to keep audio alive. Restore
      // it inline after a short delay so WebKit can finish its own reattachment
      // first; the restore is event-driven (webkitpresentationmodechanged)
      // with a page reload as a last resort.
      Future.delayed(const Duration(milliseconds: 300), _restoreVideoInline);
      // If the background queue handoff left the current video stuck on its
      // loader (not playing, not ended), start it — the user would otherwise
      // have to pause and play again manually. Bounded retries stop the moment
      // the video plays or the user/system pauses.
      if (shouldKickStuckVideo) {
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) _ensureResumedVideoPlays();
        });
      }
    }
  }

  /// Starts a video the background handoff left stuck on its loading spinner
  /// (not playing, not ended, and not paused by the user or the system).
  /// Retries briefly in case the page is still loading after a PiP restore.
  void _ensureResumedVideoPlays({int attempt = 0}) {
    if (!mounted) return;
    if (_userPausedInBackground || _systemPaused) return;
    final state = ref.read(playerProvider);
    if (state.currentVideo == null || state.isPlaying) return;
    _activeController?.evaluateJavascript(source: '''
      (function() {
        var v = $_activeVideoJs;
        if (!v || v.ended) return;
        if (v.paused) { v.play().catch(function(){}); }
      })();
    ''');
    _unmuteVideo();
    if (attempt < 2) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _ensureResumedVideoPlays(attempt: attempt + 1);
      });
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
        _lastKnownPlayingAt = DateTime.fromMillisecondsSinceEpoch(0);
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
          _onPlayerInfo(controller, args.first as Map<String, dynamic>);
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'videoState',
      callback: (args) {
        if (args.isNotEmpty && args.first is Map) {
          _onVideoState(controller, args.first as Map<String, dynamic>);
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'playerControl',
      callback: (args) {
        if (!_acceptsPlayerEvents(controller)) return;
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
        if (_acceptsPlayerEvents(controller)) _minimizeVideoTab();
      },
    );
  }

  bool _acceptsPlayerEvents(InAppWebViewController source) {
    return acceptsPlayerEvents(
      source: source,
      browseController: _webViewController,
      videoController: _videoWebViewController,
      videoTabActive: _videoTabUrl != null,
    );
  }

  @visibleForTesting
  static bool acceptsPlayerEvents({
    required Object source,
    required Object? browseController,
    required Object? videoController,
    required bool videoTabActive,
  }) {
    final expected = videoTabActive ? videoController : browseController;
    return identical(source, expected);
  }

  InAppWebViewController? get _activeController =>
      _videoWebViewController ?? _webViewController;

  Future<bool> _handleCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction createWindowAction,
  ) async {
    final url = createWindowAction.request.url;
    if (!shouldLoadPopupUrl(url: url, isAdDomain: isAdDomain)) {
      return true;
    }
    // Flood guard: even a legit-looking popup is dropped if popups have been
    // opening rapidly (the JS popupBlockerScript filters most of these; this is
    // the native backstop, e.g. target="_blank" floods that skip window.open).
    if (!shouldAllowPopup(
      sinceLastAllowed: DateTime.now().difference(_lastPopupAllowedAt),
      floodGap: _popupFloodGap,
    )) {
      return true;
    }
    _lastPopupAllowedAt = DateTime.now();
    controller.loadUrl(urlRequest: URLRequest(url: url!));
    return true;
  }

  @visibleForTesting
  static bool shouldAllowPopup({
    required Duration sinceLastAllowed,
    required Duration floodGap,
  }) {
    return sinceLastAllowed >= floodGap;
  }

  @visibleForTesting
  static bool shouldLoadPopupUrl({
    required WebUri? url,
    required bool Function(String) isAdDomain,
  }) {
    if (url == null) return false;
    final host = url.host;
    // Block blank popups (about:blank) too: popup-flood sites open a blank
    // window and redirect it to an ad landing page afterwards, which the final
    // host check alone can't catch.
    if (host.isEmpty) return false;
    return !isAdDomain(host);
  }

  /// Whether a webview-initiated navigation may proceed. Allows normal web
  /// schemes but cancels navigations to ad domains (popup floods and redirect
  /// chains that try to hijack the webview onto an ad landing page) and
  /// dangerous schemes (javascript/data/blob). Dart-initiated loads (hub →
  /// platform, opening a video) target legit domains and always pass.
  @visibleForTesting
  static bool shouldAllowNavigation({
    required String? scheme,
    required String? host,
    required bool Function(String) isAdDomain,
  }) {
    if (scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'about' ||
        scheme == 'file') {
      if (host != null && host.isNotEmpty && isAdDomain(host)) return false;
      return true;
    }
    if (scheme == 'javascript' ||
        scheme == 'data' ||
        scheme == 'blob') {
      return false;
    }
    return true;
  }

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
        // Track the new video immediately (placeholder metadata) so the mini
        // player / Now Playing don't keep showing the previous video while the
        // new one autoplays. _onPlayerInfo upgrades the title later.
        _syncTrackedVideoFromUrl(urlStr);
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

  void _onPlayerInfo(
    InAppWebViewController source,
    Map<String, dynamic> data,
  ) {
    if (!_acceptsPlayerEvents(source)) return;
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
          _lastUnmuteAttempt = DateTime.fromMillisecondsSinceEpoch(0);
          _userPausedInBackground = false;
          _systemPaused = false;
          _systemPausedElapsed = 0;
          _lastPlayInitiatedAt = DateTime.now();
          _isMusic = _isMusicUrl(video.videoUrl);
          // Upgrade metadata only — do not reset isPlaying/position, which
          // would flash the play icon and snap the slider to 0 on an
          // already-autoplaying video.
          ref.read(playerProvider.notifier).updateMetadata(video);
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

  void _onVideoState(
    InAppWebViewController source,
    Map<String, dynamic> data,
  ) {
    if (!_acceptsPlayerEvents(source)) return;
    try {
      var playing = data['playing'] == true;
      final ended = data['ended'] == true;
      final pip = data['pip'] == true;
      if (playing && !ended) {
        _lastKnownPlayingAt = DateTime.now();
        _stopPausedKeepAlive();
        _backgroundHandoffPending = false;
        // A fresh play cycle re-arms the ended-latch, so a replayed video (even
        // the same URL) can advance the queue again when it ends. _handleEnded
        // sets the latch; navigation alone no longer clears it (that caused a
        // double queue-advance while _handleEnded was in flight).
        _endedHandled = false;
      }
      // While the system has latched us as paused (another app / a call took
      // the audio session), ignore any "playing" report from the poll / JS so
      // Now Playing can't be flipped back to "playing" out of sync with the
      // actual (paused) video. But if the real <video> IS playing again, the
      // interruption ended and playback resumed (user tapped play in the page,
      // or iOS auto-resumed the element) - drop the stale latch so the player
      // button, Now Playing and the background keep-alive follow reality
      // instead of fighting it. A genuine lingering pause keeps the latch,
      // because the element keeps reporting paused.
      if (_systemPaused && playing) {
        _systemPaused = false;
        _systemPausedElapsed = 0;
        _backgroundResumeAllowed = true;
      }
      // Live streams can report non-finite position/duration - clamp to 0 so
      // Duration(milliseconds:) never receives Infinity/NaN (which throws).
      final posSec = (data['position'] as num?)?.toDouble() ?? 0;
      final durSec = (data['duration'] as num?)?.toDouble() ?? 0;
      final positionMs = posSec.isFinite ? posSec * 1000 : 0.0;
      final durationMs = durSec.isFinite ? durSec * 1000 : 0.0;
      final muted = data['muted'] == true;
      final adShowing = data['adShowing'] == true;
      // YouTube starts some videos muted (or the user previously muted); once
      // the video is actually playing, force-unmute it so audio is audible.
      // Driven by the *live* muted state reported from the page (throttled),
      // never a one-shot URL latch: YouTube can re-assert muted a moment after
      // our unmute succeeds (its own async mute/gesture state), and a latch
      // would then leave every following video stuck muted until a reload. By
      // keying on `muted`, any re-mute is detected on the next report and
      // retried until the element is actually audible.
      if (shouldAttemptUnmute(
        playing: playing,
        ended: ended,
        muted: muted,
        adShowing: adShowing,
        timeSinceLastAttempt:
            DateTime.now().difference(_lastUnmuteAttempt),
        throttle: _unmuteThrottle,
      )) {
        _lastUnmuteAttempt = DateTime.now();
        _unmuteVideo().then((audible) {
          if (mounted && audible) {
            _lastUnmuteAttempt = DateTime.now();
          }
        });
      }
      // Stuck-PiP un-stick: iOS can leave `webkitPresentationMode` stuck at
      // 'picture-in-picture' with no actual PiP window (e.g. a phantom-PiP keep-
      // alive window dismissed when a video ends). The reused <video> then
      // renders black inline — the "next video is black, close & reopen to fix"
      // bug. Restored from the documented 2026-08-10 fix. Only fires while
      // FOREGROUNDED (background phantom-PiP is intentional), only for the
      // "stuck with no window" case (a real user PiP has pipActive -> the
      // report's pipStuck is false, so it is never touched), and only after the
      // stuck state persists past a short grace period, throttled.
      final pipStuck = data['pipStuck'] == true;
      if (pipStuck && !_appIsBackgrounded) {
        _pipStuckSince ??= DateTime.now();
      } else {
        _pipStuckSince = null;
      }
      if (shouldForceVideoInline(
        pipStuck: pipStuck,
        backgrounded: _appIsBackgrounded,
        stuckDuration: _pipStuckSince == null
            ? Duration.zero
            : DateTime.now().difference(_pipStuckSince!),
        grace: _pipStuckGrace,
        timeSinceLastForce: DateTime.now().difference(_lastInlineForce),
        throttle: _inlineForceThrottle,
      )) {
        _lastInlineForce = DateTime.now();
        _forceVideoInline();
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
        } else if (ended) {
          BackgroundAudioKeepAlive.instance.stop();
          PlaybackStatsService.instance.flush();
          final id = video?.id ?? '';
          if (id.isNotEmpty) PlaybackStatsService.instance.clearProgress(id);
          _handleEnded();
        } else if (!_appIsBackgrounded) {
          BackgroundAudioKeepAlive.instance.stop();
        } else if (_backgroundResumeAllowed && !pip) {
          controlVideo('play');
        }
      } else {
        if (!playing && ended) {
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
    _lastPlayInitiatedAt = DateTime.now();
    _userPausedInBackground = false;
    _isMusic = _isMusicUrl(url);
    return video;
  }

  /// Tracks a freshly-navigated watch URL immediately (used when the video tab
  /// SPA-navigates to a related video or the queue advances), so the mini
  /// player / Now Playing stop showing the previous video. Uses placeholder
  /// metadata — [_onPlayerInfo] upgrades the real title/thumbnail afterwards.
  /// Preserves the current render state: a minimized tab stays minimized when a
  /// related video autoplays.
  void _syncTrackedVideoFromUrl(String url) {
    final current = ref.read(playerProvider).currentVideo;
    if (current?.videoUrl == url) return;
    final idMatch = RegExp(r'[?&]v=([^&]+)').firstMatch(url);
    final video = Video(
      id: idMatch != null ? idMatch.group(1)! : url,
      title: 'YouTube video',
      thumbnailUrl: idMatch != null
          ? 'https://i.ytimg.com/vi/${idMatch.group(1)!}/hqdefault.jpg'
          : '',
      videoUrl: url,
      platform: 'YouTube',
    );
    if (current == null) {
      // No video tracked yet: establish the base state (the video tab is
      // already expanded by _openVideoTab).
      if (_videoTabUrl != null) {
        ref.read(playerProvider.notifier).openVideoTab(video);
      } else {
        ref.read(playerProvider.notifier).play(video);
      }
    } else {
      // Upgrade metadata only, preserving isMinimized / isVideoTab.
      ref.read(playerProvider.notifier).updateMetadata(video);
    }
    MediaControlsService.instance.updateNowPlaying(
      title: video.title,
      artist: 'YouTube',
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: true,
      artworkUrl: video.thumbnailUrl,
    );
    _isMusic = _isMusicUrl(url);
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

  /// Advances the playback queue to the next item once the current video ends.
  /// Runs in the foreground *and* the background: while backgrounded the
  /// `ended` event still reaches Dart (the phantom-PiP / silent-loop keep-alive
  /// keeps the webview alive), and this is the only path that moves the MrPlay
  /// queue forward, so gating it on the app state was why queued videos never
  /// started after leaving the app. The next URL is routed into the active
  /// controller (video tab if present, else the browse webview), and the
  /// background keep-alive is re-applied once the next video plays.
  Future<void> _handleEnded() async {
    if (_endedHandled) return;
    _endedHandled = true;
    final items = await QueueRepository.getAll();
    if (items.isEmpty) return;
    final next = items.first;
    await QueueRepository.remove(next.id);
    exitPiP();
    if (!mounted) return;
    // Re-arm the unmute for the next item: whatever URL we route to next is a
    // new page, and its video must be allowed to start audible even if the
    // previous video was already unmuted (or the same URL is being resumed).
    _lastUnmuteAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    if (_routesToVideoTab(next.platformUrl) && _videoTabUrl != null) {
      if (_videoTabUrl == next.platformUrl) {
        // YouTube's own SPA autoplay usually wins the race and has already
        // navigated the tab to the next URL by the time `ended` reaches us.
        // Reloading here would wipe the already-buffering player and drop the
        // user onto a blank spinner (and, while suspended, can fail to restart
        // the video at all). The page is already on the right video — just make
        // sure it is actually playing and audible instead.
        _resumeOrStartActiveVideo();
      } else {
        _openVideoTab(next.platformUrl);
      }
    } else {
      // The next item plays outside the video tab (YouTube Music / another
      // platform): drop the ended video tab so it doesn't keep covering the
      // new content, and load the item in the browse webview.
      if (_videoTabUrl != null) {
        _videoTabUrl = null;
        _videoWebViewController = null;
        ref.read(playerProvider.notifier).dismiss();
      }
      loadUrl(next.platformUrl);
    }
    if (_appIsBackgrounded && _backgroundAudioEnabled) {
      // The next video must start for the background audio to survive; flag it
      // so a resume can auto-start it if the handoff left it stuck on a loader.
      _backgroundHandoffPending = true;
      _reengageBackgroundKeepAlive();
    }
  }

  /// Best-effort start for the video the page has already navigated to (used
  /// when the queue's next URL matches the tab's current URL). Resumes a paused
  /// video, replays an ended one from the start, and re-arms/retries the
  /// unmute so the next video never stays silent. A no-op when already playing.
  void _resumeOrStartActiveVideo() {
    final controller = _activeController;
    if (controller == null) return;
    controller.evaluateJavascript(source: '''
      (function() {
        var v = $_activeVideoJs;
        if (!v) return;
        if (v.ended) { try { v.currentTime = 0; } catch (e) {} }
        if (v.paused) { v.play().catch(function(){}); }
      })();
    ''');
    _unmuteVideo();
  }

  /// Best-effort background queue continuity: after a video ends while the app
  /// is backgrounded, iOS ends the PiP window and would soon suspend the
  /// webview. Waits for the next queued video to start playing, then re-applies
  /// the keep-alive (phantom-PiP for normal YouTube, silent loop for Music) so
  /// playback survives the handoff. If the next video never starts on its own
  /// (muted / paused autoplay), it is force-started before the keep-alive is
  /// re-applied, instead of silently giving up and letting iOS suspend the
  /// webview (which left the next video dead with a black + loader on reopen).
  Future<void> _reengageBackgroundKeepAlive() async {
    var playing = false;
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      playing = ref.read(playerProvider).isPlaying;
      if (playing) break;
    }
    if (!mounted || !_appIsBackgrounded || !_backgroundAudioEnabled) return;
    if (!playing) {
      // The next video hasn't started on its own. Give the freshly-loaded page
      // a moment to attach its player, then force play + unmute so the
      // keep-alive handoff isn't lost to a muted/paused autoplay.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      _resumeOrStartActiveVideo();
    }
    if (_isMusic) {
      BackgroundAudioKeepAlive.instance.start();
    } else {
      _enterPhantomPiP();
    }
  }

  void _onRemoteCommand(String command, {Duration? position}) {
    final state = ref.read(playerProvider);
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
        _applyRemoteSeek(state.position + const Duration(seconds: 15));
        break;
      case 'skipBackward':
        _applyRemoteSeek(state.position - const Duration(seconds: 15));
        break;
      case 'seek':
        if (positionMs >= 0) {
          _applyRemoteSeek(Duration(milliseconds: positionMs));
        }
        break;
    }
  }

  /// Clamps a seek target to `[0, duration]`. Negative targets land at 0 and
  /// targets past the end clamp to the duration; a zero/unknown duration is
  /// left untouched so seeking still works before metadata arrives.
  @visibleForTesting
  static Duration clampSeekTarget(Duration target, Duration duration) {
    var clamped = target.isNegative ? Duration.zero : target;
    if (duration > Duration.zero && clamped > duration) clamped = duration;
    return clamped;
  }

  /// Whether the unmute should run now, based on the live player state.
  /// Only when the active video is actually playing, is muted, and no ad is
  /// showing (the ad-blocker owns the mute during ads), throttled so YouTube's
  /// async re-mute is retried without hammering the webview every report.
  @visibleForTesting
  static bool shouldAttemptUnmute({
    required bool playing,
    required bool ended,
    required bool muted,
    required bool adShowing,
    required Duration timeSinceLastAttempt,
    required Duration throttle,
  }) {
    if (!playing || ended) return false;
    if (!muted) return false;
    if (muted && adShowing) return false;
    return timeSinceLastAttempt >= throttle;
  }

  /// Whether the stuck-PiP un-stick should run now. Only when the report says
  /// the video is "stuck with no window" (`pipStuck` is already
  /// mode==PiP && no pictureInPictureElement), the app is foregrounded, the
  /// stuck state has persisted past the grace period (so a legit PiP enter/exit
  /// transition can't be canceled), and the throttle since the last force has
  /// elapsed (so it can't hammer the webview on every state report).
  @visibleForTesting
  static bool shouldForceVideoInline({
    required bool pipStuck,
    required bool backgrounded,
    required Duration stuckDuration,
    required Duration grace,
    required Duration timeSinceLastForce,
    required Duration throttle,
  }) {
    if (!pipStuck || backgrounded) return false;
    if (stuckDuration < grace) return false;
    return timeSinceLastForce >= throttle;
  }

  /// Applies a remote (lock-screen / Control Center) seek: updates the player
  /// position, seeks the active `<video>`, and lets [_resumeAfterRemoteSeek]
  /// decide whether to re-start playback after iOS's scrub-pause.
  void _applyRemoteSeek(Duration target) {
    final clamped = clampSeekTarget(target, ref.read(playerProvider).duration);
    final now = DateTime.now();
    // Snapshot whether the video was playing at the START of the scrub. iOS
    // keeps the element paused for the whole drag, so checking `isPlaying`
    // later (or a short "recently playing" window) fails on any drag longer
    // than a couple of seconds — leaving the video stuck on the spinner.
    if (now.difference(_lastSeekDragTick) >=
        const Duration(milliseconds: 700)) {
      _wasPlayingAtSeek =
          ref.read(playerProvider).isPlaying ||
              now.difference(_lastKnownPlayingAt) < const Duration(seconds: 5);
    }
    _lastSeekDragTick = now;
    ref.read(playerProvider.notifier).seekTo(clamped);
    controlVideo('seek', position: clamped.inMilliseconds / 1000.0);
    _resumeAfterRemoteSeek();
  }

  /// Debounced resume after a lock-screen / Control Center seek. iOS pauses the
  /// `<video>` while the user drags the scrubber and never sends a follow-up
  /// play command, so the element can be left mid-seek — YouTube shows its
  /// buffering spinner ("loading") and playback never continues until the user
  /// nudges the timeline again. If the video was playing when the scrub began
  /// (and wasn't deliberately paused), re-start playback at the new position
  /// once the drag settles. The timer resets on every seek event, so a long
  /// drag only resumes when the finger lifts.
  void _resumeAfterRemoteSeek() {
    _remoteSeekResumeTimer?.cancel();
    _remoteSeekResumeTimer = Timer(const Duration(milliseconds: 350), () {
      _remoteSeekResumeTimer = null;
      if (!mounted) return;
      if (!_wasPlayingAtSeek && !ref.read(playerProvider).isPlaying) return;
      // With background audio off the app intentionally stops in the background;
      // don't fight that from a Control Center scrub.
      if (_appIsBackgrounded && !_backgroundAudioEnabled) return;
      resumePlayback();
    });
  }

  /// Pauses playback as an explicit user action (lock screen / Control Center
  /// / sleep timer). While backgrounded, system-forced pauses are auto-resumed
  /// (for YouTube Music); user pauses must not be fought.
  void userInitiatedPause() {
    _backgroundResumeAllowed = false;
    _lastKnownPlayingAt = DateTime.fromMillisecondsSinceEpoch(0);
    _userPausedInBackground = true;
    _backgroundHandoffPending = false;
    _wasPlayingAtSeek = false;
    if (!_appIsBackgrounded) {
      BackgroundAudioKeepAlive.instance.stop();
      _stopPausedKeepAlive();
    } else if (_backgroundAudioEnabled && !_systemPaused) {
      // Pausing while backgrounded ends the phantom-PiP keep-alive (iOS closes
      // the PiP window on pause), which lets iOS suspend the WebView — and then
      // the lock screen / Control Center play button can no longer reach it
      // (you'd have to reopen the app). Keep the silent loop alive AND keep
      // re-asserting phantom PiP so the WebContent process stays reachable for
      // a later play — for regular YouTube too, not just Music.
      BackgroundAudioKeepAlive.instance.start();
      _startPausedKeepAlive();
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
    _lastKnownPlayingAt = DateTime.fromMillisecondsSinceEpoch(0);
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
    _lastPlayInitiatedAt = DateTime.now();
    _lastKnownPlayingAt = DateTime.now();
    _backgroundResumeAllowed = true;
    _userPausedInBackground = false;
    _backgroundHandoffPending = false;
    _stopPausedKeepAlive();
    ref.read(playerProvider.notifier).resume();
    if (_appIsBackgrounded && _backgroundAudioEnabled && !_isMusic) {
      // Resuming from the lock screen: re-engage the phantom-PiP keep-alive,
      // which both resumes the paused video and keeps the WebContent process
      // alive for continued background playback.
      _enterPhantomPiP();
    } else {
      controlVideo('play');
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
    _lastUnmuteAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastPlayInitiatedAt = DateTime.now();
    ref.read(playerProvider.notifier).videoTabActive();
    _videoTabIntro = true;
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
        _lastPlayInitiatedAt = DateTime.now();
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

  /// JS body for [_unmuteVideo]. Un-mutes the actively playing `<video>` and
  /// unlocks YouTube's player — but ONLY when the video is muted and no ad is
  /// showing. The ad-blocker (`adFallbackSkipScript`) deliberately keeps the
  /// player muted during ads and re-mutes on any `volumechange`; unmuting here
  /// would burst ad audio and set up a mute/unmute ping-pong. The unlock is
  /// scoped to `#movie_player` so it can't click a muted feed preview's button.
  @visibleForTesting
  static const String unmuteVideoScript = '''
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
      var player = null;
      try { player = document.getElementById('movie_player'); } catch (e) {}
      var adShowing = false;
      try { adShowing = !!(player && player.classList.contains('ad-showing')); } catch (e) {}
      if (!main.muted && main.volume > 0) return { audible: true };
      if (adShowing) return { audible: false };
      main.muted = false;
      main.defaultMuted = false;
      main.volume = 1;
      // Unlock YouTube's player so autoplay can advance. Its own API is the
      // reliable path; clicking the real unmute button (hidden or not) is the
      // fallback. Only touch the player when we actually had to unmute, so a
      // user's preferred volume is never overridden on an already-audible video.
      try {
        if (player) {
          if (typeof player.unMute === 'function') { player.unMute(); }
          else if (typeof player.setVolume === 'function') { player.setVolume(100); }
        }
      } catch (e) {}
      try {
        var btn = player && player.querySelector('.ytp-unmute-widget button, [class*="unmute"] button');
        if (btn && typeof btn.click === 'function') { btn.click(); }
      } catch (e) {}
      return { audible: !main.muted && main.volume > 0 };
    })();
  ''';

  /// Un-mutes the actively playing video and unlocks YouTube's player.
  ///
  /// YouTube sometimes starts playback muted (or the user previously muted it),
  /// showing the "tap to unmute" overlay. Clearing `muted` on the `<video>`
  /// element alone leaves YouTube's own player state locked in "awaiting
  /// gesture" — which stops a mix from auto-advancing to the next video in the
  /// background. So we also trigger YouTube's own unmute (player API, falling
  /// back to clicking the real button, which fires even when the widget is
  /// CSS-hidden) to clear that state. Skips while an ad is showing so it never
  /// fights the ad-blocker. Returns whether the active video is now audible, so
  /// callers can retry until it is.
  Future<bool> _unmuteVideo() async {
    final controller = _activeController;
    if (controller == null) return false;
    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: unmuteVideoScript,
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
    _lastUnmuteAttempt = DateTime.fromMillisecondsSinceEpoch(0);
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

  /// Lightweight stuck-PiP un-stick: sets the video back inline when it is
  /// stuck in PiP presentation mode with no visible PiP window (the black
  /// video case). Re-checks the stuck condition synchronously so it can never
  /// fight a real PiP window (pictureInPictureElement is set there).
  void _forceVideoInline() {
    _activeController?.evaluateJavascript(source: '''
      (function() {
        var v = $_activeVideoJs;
        if (!v || !v.webkitSetPresentationMode) return;
        if (v.webkitPresentationMode !== 'picture-in-picture') return;
        if (document.pictureInPictureElement) return;
        try { v.webkitSetPresentationMode('inline'); } catch (e) {}
      })();
    ''');
  }

  /// Re-asserts phantom PiP WITHOUT resuming the video. While a video is
  /// paused in the background, the phantom-PiP window is what keeps the
  /// WebView's WebContent process alive; if iOS dismisses it, a lock-screen
  /// play can no longer reach the video (you'd have to reopen the app). This
  /// keeps the window alive so that never happens. No-op when already in PiP.
  void _reassertPhantomPip() {
    _activeController?.evaluateJavascript(source: '''
      (function() {
        var v = $_activeVideoJs;
        if (!v || !v.webkitSetPresentationMode) return;
        if (v.webkitPresentationMode === 'picture-in-picture') return;
        try { v.webkitSetPresentationMode('picture-in-picture'); } catch (e) {}
      })();
    ''');
  }

  /// Periodically re-asserts phantom PiP while a video is paused in the
  /// background, so the WebContent process stays reachable for a lock-screen
  /// play. Stops itself once playback resumes, the app returns to the
  /// foreground, or background audio is off.
  void _startPausedKeepAlive() {
    _pausedKeepAliveTimer?.cancel();
    _pausedKeepAliveTimer = Timer.periodic(_pausedKeepAliveInterval, (_) {
      if (!mounted) return;
      if (!_appIsBackgrounded || !_backgroundAudioEnabled) {
        _stopPausedKeepAlive();
        return;
      }
      if (ref.read(playerProvider).isPlaying || !_userPausedInBackground) {
        _stopPausedKeepAlive();
        return;
      }
      _reassertPhantomPip();
    });
  }

  void _stopPausedKeepAlive() {
    _pausedKeepAliveTimer?.cancel();
    _pausedKeepAliveTimer = null;
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
  /// confirm 'inline', verifies rendering, and only reloads the page as a true
  /// last resort. The webview can be momentarily un-attached right after
  /// resume (callAsyncJavaScript throws) or the mode-change event can lag, so
  /// failures are retried instead of instantly reloading — an eager reload is
  /// what dropped the user onto the black player + loader on open.
  Future<void> _restoreVideoInline() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
      }
      final ok = await _tryRestoreInlineOnce();
      if (ok) return;
    }
    debugPrint('[MrPlay] inline restore failed after retries, reloading');
    _activeController?.reload();
    // After the reload, make sure the freshly-loaded watch page actually
    // starts (and is audible) instead of sitting on its loader.
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _resumeOrStartActiveVideo();
    });
  }

  /// One inline-restore attempt. Returns true when there is nothing to restore
  /// or the restore succeeded; false on timeout / no-render / API error / a
  /// not-yet-attached webview, so the caller can retry.
  Future<bool> _tryRestoreInlineOnce() async {
    final controller = _activeController;
    if (controller == null) return true;
    try {
      final result = await controller.callAsyncJavaScript(functionBody: '''
        var videos = document.querySelectorAll('video');
        var video = null;
        for (var i = 0; i < videos.length; i++) {
          if (!videos[i].paused && !videos[i].ended) { video = videos[i]; break; }
        }
        if (!video && videos.length > 0) video = videos[0];
        if (!video) return { ok: true, reason: 'no-video' };
        // A REAL user PiP window (mini-bar swipe / PiP button) must never be
        // force-exited on app resume — only the phantom keep-alive is restored
        // inline. Leave the window alone.
        if (document.pictureInPictureElement) {
          return { ok: true, reason: 'real-pip' };
        }
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
        debugPrint('[MrPlay] inline restore attempt failed: '
            '${value is Map ? value['reason'] : 'unknown'}');
      }
      return ok;
    } catch (e) {
      debugPrint('[MrPlay] _restoreVideoInline error (will retry): $e');
      return false;
    }
  }

  /// Enters phantom PiP on background and makes sure the video is actually
  /// playing inside the PiP session. iOS pauses the webview video when the app
  /// backgrounds; the PiP handoff alone leaves it paused (no audio). We wait for
  /// the mode-change event, then resume playback so the PiP/AVFoundation session
  /// keeps the audio alive. Retried once: the very first background of a session
  /// sports a cold PiP pipeline, so the handoff can lose the race against
  /// suspension (audio dies for that one background until the user hits play
  /// from the notification center).
  Future<void> _enterPhantomPiP() async {
    if (await _tryEnterPhantomPiP()) return;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    if (!await _tryEnterPhantomPiP()) {
      debugPrint('[MrPlay] phantom PiP retry failed');
    }
  }

  Future<bool> _tryEnterPhantomPiP() async {
    final controller = _activeController;
    if (controller == null) return false;
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
      final ok = value is Map && value['ok'] == true;
      if (!ok) {
        debugPrint('[MrPlay] phantom PiP failed: ${value is Map ? value['reason'] : 'unknown'}');
      }
      return ok;
    } catch (_) {
      // WebContent may already be suspended; nothing else we can do from Dart.
      return false;
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
          var adShowing = false;
          try {
            pipStuck = (typeof v.webkitPresentationMode !== 'undefined') &&
                       v.webkitPresentationMode === 'picture-in-picture';
            pipActive = (typeof document.pictureInPictureElement !== 'undefined' &&
                         !!document.pictureInPictureElement);
          } catch (e) {}
          try {
            var playerEl = v.closest ? v.closest('.html5-video-player') : null;
            if (!playerEl) playerEl = document.querySelector('.html5-video-player');
            adShowing = !!(playerEl && playerEl.classList.contains('ad-showing'));
          } catch (e) {}
          return {
            playing: !v.paused && !v.ended,
            position: isFinite(v.currentTime) ? v.currentTime : 0,
            duration: isFinite(v.duration) ? v.duration : 0,
            ended: !!v.ended,
            muted: !!v.muted,
            adShowing: adShowing,
            pip: pipStuck || pipActive,
            pipActive: pipActive,
            pipStuck: pipStuck && !pipActive
          };
        })();
      ''');
      if (result is Map) {
        _onVideoState(controller, Map<String, dynamic>.from(result));
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
              if (_adBlockEnabled) ..._adBlockScripts(),
              UserScript(
                source: ContentBlockerJS.popupBlockerScript,
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
              allowBackgroundAudioPlaying: true,
              allowsPictureInPictureMediaPlayback: true,
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
              final allowed = shouldAllowNavigation(
                scheme: url?.scheme.toLowerCase(),
                host: url?.host,
                isAdDomain: isAdDomain,
              );
              return allowed
                  ? NavigationActionPolicy.ALLOW
                  : NavigationActionPolicy.CANCEL;
            },
            onCreateWindow: _handleCreateWindow,
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
                      if (_adBlockEnabled) ..._adBlockScripts(),
                      UserScript(
                        source: ContentBlockerJS.popupBlockerScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
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
                      allowBackgroundAudioPlaying: true,
                      allowsPictureInPictureMediaPlayback: true,
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
                      final allowed = shouldAllowNavigation(
                        scheme: url?.scheme.toLowerCase(),
                        host: url?.host,
                        isAdDomain: isAdDomain,
                      );
                      return allowed
                          ? NavigationActionPolicy.ALLOW
                          : NavigationActionPolicy.CANCEL;
                    },
                    onCreateWindow: _handleCreateWindow,
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
    _videoWebViewController = null;
    _pendingVideoUrl = null;
    _tabSwipeOffset = 0;
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
