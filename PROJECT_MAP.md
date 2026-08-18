MrPlay - Project Map

> **Implementation Status (2026-08-02)** — the sections below describe the original plan.
> Actual stack: **Riverpod** (not bloc), **flutter_inappwebview** (not webview_flutter),
> iOS-only (no android/ folder). Implemented on top of the plan:
> - Auto-PiP on app background + swipe-down-to-PiP from full/mini player
> - PiP search-shelter: video survives YouTube SPA navigation via `history.pushState`/
>   `replaceState` wrappers + `yt-navigate-start`/`ytm-navigate-start` hooks (fixed 2026-08-02)
> - Generic content blocker (`content_blocker_js.dart`) + YouTube UI cleanup scripts
> - Silent-audio background keep-alive (only while media is playing)
> - AdMob adaptive banner (test IDs while in development)
> - Spotlight indexing, home widget, share extension
> - **Watch Later queue** (Hive box `watch_later`, bookmark button in full player, Library tabs)
> - **Sleep timer** (`sleep_timer_service.dart`, bedtime button in full player, 5–60 min)
> - **Custom bookmarks** (Hive box `custom_bookmarks`, "+" card in hub grid, long-press to delete)
> - Fixes 2026-08-02: live-stream `Infinity` duration crash (JS + Dart guards),
>   Slider/progress clamping, mini-player drag visual feedback
> - Fixes 2026-08-04: mini player now appears for YouTube SPA navigations
>   (`onUpdateVisitedHistory` keeps the current URL fresh and runs the watch-page
>   title extraction / resume-seek that `onLoadStop` misses); webview overlay gains
>   a show-mini-player button (bottom: 140, PiP moved to 110); background/lock-screen
>   audio hardened: system-forced webview pauses are auto-resumed while backgrounded
>   unless the pause was user-initiated (lock screen / Control Center / sleep timer
>   go through `userInitiatedPause()`); black in-page video fixed by exiting PiP
>   when the app resumes (auto-PiP on background/transient-inactive was never
>   undone, leaving the "playing in PiP" placeholder stuck on the reused element)
> - Known pending: AdMob `GADApplicationIdentifier` in Info.plist is the TEST app id —
>   replace with the real one before release; dependencies outdated (riverpod 3.x, admob 9.x)
> - Fixes 2026-08-07: banner close button tappable again (it overflowed the
>   Stack's bounds at top:-20/right:-20 and Flutter never hit-tests outside the
>   Stack rect — space is now reserved via padding so the whole 44px circle is
>   inside); black watch-page video fixed for good: `popstate` no longer
>   shelters when LANDING on a /watch page, and `restoreShelteredIntoPlayer`
>   (on `playing` + 800ms interval) puts YouTube's reused `<video>` element
>   back into the visible player when a watch page claims the sheltered one
> - Fixes 2026-08-10: black in-page video (audio + native YouTube controls
>   working, frames only visible in PiP) root-caused to the video being stuck
>   in PiP presentation mode with no visible PiP window — iOS leaves
>   `webkitPresentationMode == 'picture-in-picture'` after the PiP window is
>   dismissed, and the 1s force-back loop that masked it had been removed.
>   Fixed with a smart un-stick guard instead of restoring the loop (which
>   also killed intentional PiP): Dart tracks `_pipRequestedByUser` (set by
>   the PiP button / swipe-down-to-PiP, cleared on exit/new video/app
>   resume/dismiss), and any `videoState` report of `pip == true` that was
>   NOT requested while foregrounded is forced back inline via
>   `ensureVideoVisible()`; collapsing the full player to the mini player
>   runs the same check unless PiP was requested
> - Fixes 2026-08-13: seek slider/timer frozen + black video on minimize.
>   The full player is an opaque overlay (thumbnail slot) that hides the
>   webview; iOS throttles the page's own `timeupdate`/`setInterval` heartbeats
>   while it's covered, so `position`/`duration` stopped updating and the
>   slider had no live duration to seek against. Added a Dart-side
>   `_pollVideoState` (500ms `evaluateJavascript`) that starts when a video is
>   tracked, so position/duration stay fresh regardless of page throttling.
>   `controlVideo` now targets the actively-playing `<video>` (not the first
>   one) for play/pause/seek/captions/fullscreen. Removed `scrollVideoIntoView`
>   from the alignment watchdog (the full player no longer shows the live
>   webview video, so scrolling the hidden page only left the user stranded at
>   the player after minimize). Minimize now re-runs `ensureVideoVisible` after
>   a short delay to clear the stuck-PiP black frame. Share Link button fixed:
>   iPad requires a non-null `sharePositionOrigin` (popover) or the share
>   sheet is silently dropped; URL falls back videoUrl → YouTube id → current
>   URL.
> - Fixes 2026-08-13 (2): full player "down" button now enters PiP on collapse.
>   Collapsing the full player straight back to the native page left the
>   in-page `<video>` black (frames only render in the PiP pipeline on iOS).
>   The down button now calls `enterPiP()` before `minimize()` — matching the
>   swipe-down gesture — so the video stays visible in its floating window
>   instead of a black inline frame. `enterPiP`/`exitPiP`/`togglePictureInPicture`
>   also now target the actively-playing `<video>`.
> - **Native AVPlayer migration (2026-08)** for YouTube playback: YouTube URLs are
>   routed off the WebView to a native `video_player` pipeline — `youtube_explode_dart`
>   (`lib/services/youtube_stream_resolver.dart`) resolves a highest-bitrate muxed
>   stream (HLS fallback; `androidSdkless`+`androidVr` clients, `tv` fallback), and
>   `lib/services/native_youtube_player.dart` plays it with `allowBackgroundPlayback`.
>   Lock-screen/remote controls and background audio reuse the existing
>   `com.mrplay/media` MediaControlsService (no `audio_service`), extended with an
>   `interruption` method tied to a native AVAudioSession interruption observer in
>   `AppDelegate.swift`. Native PiP uses a new `PiPBridge.swift` + `com.mrplay/pip`
>   channel (`AVPictureInPictureController` over the AVPlayerLayer; the video_player
>   surface must use `viewType: platformView` on iOS so the layer is findable).
>   `full_player.dart` renders the native surface (plus buffering spinner and a
>   skip/retry error overlay); captions/fullscreen buttons are hidden for native.
>   Non-YouTube URLs keep the WebView path unchanged.

Overview
MrPlay is a multi-platform video/content hub iOS app built with Flutter. It provides a native iOS experience with a platform hub, persistent WebView-based video playback, background audio, mini player overlay, and JavaScript-based ad blocking on YouTube mobile web.
Architecture
plain
┌─────────────────────────────────────────────┐
│              FLUTTER LAYER                  │
│  ┌─────────┐  ┌─────────┐  ┌───────────┐  │
│  │  Hub    │  │ WebView │  │  Mini     │  │
│  │  Screen │  │ Screen  │  │  Player   │  │
│  └─────────┘  └─────────┘  └───────────┘  │
│  ┌─────────┐  ┌─────────┐  ┌───────────┐  │
│  │Settings │  │ Search  │  │  Favorites│  │
│  └─────────┘  └─────────┘  └───────────┘  │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │  JavaScript ↔ Dart Bridge          │   │
│  │  (Extract video info, control YT)  │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
                    │
┌─────────────────────────────────────────────┐
│         PLATFORM CHANNELS (iOS Native)      │
│  ┌─────────┐  ┌───────────────────────────┐ │
│  │  iOS    │  │  Background Audio         │ │
│  │  Swift  │  │  (AVAudioSession)         │ │
│  │  Code   │  │                           │ │
│  └─────────┘  │  Notification Controls    │ │
│               │  (MPNowPlayingInfoCenter) │ │
│               │                           │ │
│               │  WebView Audio Persistence │ │
│               └───────────────────────────┘ │
└─────────────────────────────────────────────┘
Tech Stack
Table
Component	Technology
Framework	Flutter 3.22+
Language	Dart
iOS WebView	webview_flutter (WKWebView)
Background Audio	audio_service + custom iOS native bridging
Notifications	audio_service (MPNowPlayingInfoCenter)
State Management	flutter_bloc or Provider
Local Storage	shared_preferences + hive
HTTP	dio
JSON	json_serializable
Icons	flutter_svg
URL Launcher	url_launcher
Share	share_plus
Path Provider	path_provider
Project Structure
plain
mrplay/
├── android/                          # Android config (minimized)
├── ios/                              # iOS native code
│   ├── Runner/
│   │   ├── AppDelegate.swift         # Native iOS entry point
│   │   ├── Info.plist                # iOS permissions
│   │   └── ...
│   └── Runner.xcworkspace/
├── lib/
│   ├── main.dart                     # App entry point
│   ├── app.dart                      # MaterialApp, routes, theme
│   ├── core/                         # Core utilities
│   │   ├── constants/
│   │   │   ├── app_constants.dart    # App name, version, URLs
│   │   │   ├── platform_constants.dart # Platform list, icons, URLs
│   │   │   └── youtube_js.dart       # JavaScript injection scripts
│   │   ├── theme/
│   │   │   ├── app_theme.dart        # Light/dark theme
│   │   │   └── app_colors.dart       # Color palette
│   │   ├── utils/
│   │   │   ├── webview_utils.dart    # WebView helpers
│   │   │   ├── audio_utils.dart      # Audio session helpers
│   │   │   └── notification_utils.dart # Notification helpers
│   │   └── extensions/
│   │       └── string_extensions.dart
│   ├── data/                         # Data layer
│   │   ├── models/
│   │   │   ├── platform_model.dart   # Platform data model
│   │   │   ├── video_model.dart      # Video metadata model
│   │   │   └── settings_model.dart   # User settings model
│   │   ├── repositories/
│   │   │   ├── platform_repository.dart
│   │   │   ├── favorites_repository.dart
│   │   │   └── settings_repository.dart
│   │   └── datasources/
│   │       ├── local/
│   │       │   ├── shared_prefs.dart
│   │       │   └── hive_boxes.dart
│   │       └── remote/
│   │           └── youtube_scraper.dart
│   ├── domain/                       # Business logic
│   │   ├── entities/
│   │   │   ├── platform_entity.dart
│   │   │   └── video_entity.dart
│   │   └── usecases/
│   │       ├── get_platforms.dart
│   │       ├── toggle_favorite.dart
│   │       └── get_favorites.dart
│   ├── presentation/                 # UI Layer
│   │   ├── bloc/                     # State management
│   │   │   ├── hub/
│   │   │   │   ├── hub_bloc.dart
│   │   │   │   ├── hub_event.dart
│   │   │   │   └── hub_state.dart
│   │   │   ├── webview/
│   │   │   │   ├── webview_bloc.dart
│   │   │   │   ├── webview_event.dart
│   │   │   │   └── webview_state.dart
│   │   │   ├── miniplayer/
│   │   │   │   ├── miniplayer_bloc.dart
│   │   │   │   ├── miniplayer_event.dart
│   │   │   │   └── miniplayer_state.dart
│   │   │   └── settings/
│   │   │       ├── settings_bloc.dart
│   │   │       ├── settings_event.dart
│   │   │       └── settings_state.dart
│   │   ├── pages/
│   │   │   ├── hub_page.dart         # Main hub screen
│   │   │   ├── webview_page.dart     # WebView screen
│   │   │   ├── settings_page.dart    # Settings screen
│   │   │   └── favorites_page.dart   # Favorites screen
│   │   ├── widgets/
│   │   │   ├── platform_card.dart    # Hub grid item
│   │   │   ├── mini_player.dart      # Bottom mini player
│   │   │   ├── persistent_webview.dart # Hidden persistent WebView
│   │   │   ├── custom_app_bar.dart   # App bar components
│   │   │   ├── search_bar.dart       # Search widget
│   │   │   ├── loading_indicator.dart
│   │   │   └── error_widget.dart
│   │   └── router/
│   │       └── app_router.dart       # Navigation routes
│   └── services/                     # Platform services
│       ├── audio_service.dart          # Background audio management
│       ├── notification_service.dart   # Notification center controls
│       └── js_bridge_service.dart      # JS ↔ Dart communication
├── test/                             # Unit tests
├── pubspec.yaml                      # Dependencies
└── README.md
Core Features & Implementation
1. Hub Screen (Home)
UI:
Gradient background (blue/green)
Settings icon (top-left), Premium icon (top-right)
"MrPlay" title (large, white)
Rounded search bar (white, placeholder "Search")
GridView of platform shortcuts (4 columns, 20+ platforms)
Each card: platform icon (SVG/PNG) + name below
Platforms List:
dart
final platforms = [
  PlatformModel(name: 'YouTube', url: 'https://m.youtube.com', icon: 'youtube.svg', category: 'video'),
  PlatformModel(name: 'Music', url: 'https://music.youtube.com', icon: 'music.svg', category: 'music'),
  PlatformModel(name: 'Twitch', url: 'https://m.twitch.tv', icon: 'twitch.svg', category: 'video'),
  PlatformModel(name: 'Rumble', url: 'https://rumble.com', icon: 'rumble.svg', category: 'video'),
  PlatformModel(name: 'Duolingo', url: 'https://duolingo.com', icon: 'duolingo.svg', category: 'education'),
  PlatformModel(name: 'Busuu', url: 'https://busuu.com', icon: 'busuu.svg', category: 'education'),
  PlatformModel(name: 'Babbel', url: 'https://babbel.com', icon: 'babbel.svg', category: 'education'),
  PlatformModel(name: 'Memrise', url: 'https://memrise.com', icon: 'memrise.svg', category: 'education'),
  PlatformModel(name: 'Mondly', url: 'https://mondly.com', icon: 'mondly.svg', category: 'education'),
  PlatformModel(name: 'Instagram', url: 'https://instagram.com', icon: 'instagram.svg', category: 'social'),
  PlatformModel(name: 'Reddit', url: 'https://reddit.com', icon: 'reddit.svg', category: 'social'),
  PlatformModel(name: 'Facebook', url: 'https://facebook.com', icon: 'facebook.svg', category: 'social'),
  PlatformModel(name: 'X', url: 'https://x.com', icon: 'x.svg', category: 'social'),
  PlatformModel(name: 'Disney+', url: 'https://disneyplus.com', icon: 'disney.svg', category: 'streaming'),
  PlatformModel(name: 'HBO Max', url: 'https://max.com', icon: 'hbo.svg', category: 'streaming'),
  PlatformModel(name: 'Prime Video', url: 'https://primevideo.com', icon: 'prime.svg', category: 'streaming'),
  PlatformModel(name: 'Pinterest', url: 'https://pinterest.com', icon: 'pinterest.svg', category: 'social'),
  PlatformModel(name: 'Quora', url: 'https://quora.com', icon: 'quora.svg', category: 'social'),
  PlatformModel(name: '9gag', url: 'https://9gag.com', icon: '9gag.svg', category: 'social'),
  PlatformModel(name: 'iFunny', url: 'https://ifunny.co', icon: 'ifunny.svg', category: 'social'),
];
Navigation:
Tap platform → push WebViewPage with platform URL
Search bar → opens search overlay (native UI, searches within selected platform)
2. WebView Screen
Architecture:
Uses webview_flutter package
Loads platform URL (e.g., https://m.youtube.com)
CRITICAL: For YouTube, inject JavaScript for ad blocking
For non-YouTube platforms, load normally
JavaScript Injection (YouTube Ad Blocking):
dart
// lib/core/constants/youtube_js.dart
class YouTubeJS {
  static const String adBlockScript = '''
    (function() {
      // Hide ad containers
      const adSelectors = [
        '.video-ads',
        '.ytp-ad-module',
        '.ytp-ad-overlay-container',
        '.ytp-ad-text-overlay',
        '#player-ads',
        '.ytp-ad-skip-button-slot',
        'ytd-display-ad-renderer',
        'ytd-promoted-sparkles-web-renderer',
        'ytd-video-masthead-ad-renderer',
        'ytd-banner-promo-renderer',
        '.ytd-ad-slot-renderer',
        'ytd-in-feed-ad-layout-renderer',
        'ytd-ad-slot-renderer',
        '.ytp-ad-progress-list',
        '.ytp-ad-duration-remaining'
      ];

      function hideAds() {
        adSelectors.forEach(selector => {
          document.querySelectorAll(selector).forEach(el => {
            el.style.display = 'none';
            el.style.visibility = 'hidden';
            el.style.opacity = '0';
          });
        });
      }

      // Run immediately and on DOM changes
      hideAds();
      const observer = new MutationObserver(hideAds);
      observer.observe(document.body, { childList: true, subtree: true });

      // Auto-skip skippable ads
      setInterval(() => {
        const skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button');
        if (skipBtn) skipBtn.click();

        const video = document.querySelector('video');
        const adModule = document.querySelector('.ytp-ad-module');
        if (adModule && video) {
          // Speed through unskippable ads
          video.playbackRate = 16;
          setTimeout(() => { video.playbackRate = 1; }, 500);
        }
      }, 1000);

      // Report player state to Flutter
      setInterval(() => {
        const video = document.querySelector('video');
        const title = document.querySelector('h1.title, .slim-video-information-title, .ytp-title')?.textContent || '';
        const channel = document.querySelector('.ytd-channel-name a, .slim-owner-channel-name a')?.textContent || '';
        const thumb = document.querySelector('.ytp-cued-thumbnail-overlay-image')?.style.backgroundImage || '';

        if (window.flutter_inappwebview) {
          window.flutter_inappwebview.callHandler('videoState', {
            isPlaying: video ? !video.paused : false,
            currentTime: video ? video.currentTime : 0,
            duration: video ? video.duration : 0,
            title: title,
            channel: channel,
            thumbnail: thumb
          });
        }
      }, 500);
    })();
  ''';

  static const String pauseScript = 'document.querySelector("video").pause();';
  static const String playScript = 'document.querySelector("video").play();';
  static const String seekScript = '''
    (function(time) {
      const video = document.querySelector("video");
      if (video) video.currentTime = time;
    })(%s);
  ''';
}
WebView Configuration:
dart
WebViewController controller = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..setBackgroundColor(const Color(0x00000000))
  ..setNavigationDelegate(NavigationDelegate(
    onPageFinished: (String url) {
      if (url.contains('youtube.com')) {
        controller.runJavaScript(YouTubeJS.adBlockScript);
      }
    },
  ))
  ..addJavaScriptChannel(
    'videoState',
    onMessageReceived: (JavaScriptMessage message) {
      // Parse video state and update MiniPlayerBloc
      final data = jsonDecode(message.message);
      miniPlayerBloc.add(VideoStateUpdated(data));
    },
  )
  ..loadRequest(Uri.parse('https://m.youtube.com'));
3. Mini Player (Picture-in-Picture)
Architecture:
Mini player is a persistent widget that sits above all screens
It does NOT navigate away from WebView—it hides it and shows a mini representation
WebView stays alive in background (hidden or mini)
Implementation:
dart
// lib/presentation/widgets/persistent_webview.dart
class PersistentWebView extends StatefulWidget {
  @override
  _PersistentWebViewState createState() => _PersistentWebViewState();
}

class _PersistentWebViewState extends State<PersistentWebView> {
  late WebViewController _controller;
  bool _isMini = false;
  VideoInfo? _currentVideo;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('videoState', onMessageReceived: _onVideoState)
      ..loadRequest(Uri.parse('https://m.youtube.com'));
  }

  void _onVideoState(JavaScriptMessage message) {
    final data = jsonDecode(message.message);
    setState(() {
      _currentVideo = VideoInfo.fromJson(data);
    });
  }

  void minimize() => setState(() => _isMini = true);
  void maximize() => setState(() => _isMini = false);
  void close() {
    _controller.loadRequest(Uri.parse('about:blank'));
    setState(() {
      _isMini = false;
      _currentVideo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentVideo == null) return SizedBox.shrink();

    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      height: _isMini ? 70 : MediaQuery.of(context).size.height,
      width: _isMini ? MediaQuery.of(context).size.width : null,
      child: _isMini 
        ? MiniPlayerWidget(
            video: _currentVideo!,
            onTap: maximize,
            onClose: close,
            controller: _controller,
          )
        : WebViewWidget(controller: _controller),
    );
  }
}
Mini Player Widget:
dart
// lib/presentation/widgets/mini_player.dart
class MiniPlayerWidget extends StatelessWidget {
  final VideoInfo video;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final WebViewController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 70,
        color: Colors.black87,
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 120,
              child: video.thumbnailUrl.isNotEmpty
                ? Image.network(video.thumbnailUrl, fit: BoxFit.cover)
                : Container(color: Colors.grey),
            ),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white)),
                  Text(video.channel, maxLines: 1, style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            // Controls
            IconButton(
              icon: Icon(video.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
              onPressed: () {
                controller.runJavaScript(
                  video.isPlaying ? YouTubeJS.pauseScript : YouTubeJS.playScript
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.close, color: Colors.white),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
App Structure with Persistent WebView:
dart
// lib/app.dart
class MrPlayApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            // Main navigation (Hub, Settings, etc.)
            Navigator(
              onGenerateRoute: AppRouter.onGenerateRoute,
            ),
            // Persistent WebView layer (hidden when not in use)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: PersistentWebView(),
            ),
          ],
        ),
      ),
    );
  }
}
4. Background Audio (Native iOS)
CRITICAL: This requires native iOS code. Flutter alone cannot keep WebView audio alive in background.
iOS Native Code (Swift):
swift
// ios/Runner/AppDelegate.swift
import UIKit
import Flutter
import AVFoundation
import MediaPlayer

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  var audioSession: AVAudioSession?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Setup audio session for background playback
    setupAudioSession()

    // Setup method channel for Flutter communication
    let controller = window?.rootViewController as! FlutterViewController
    let audioChannel = FlutterMethodChannel(
      name: "com.mrplay/audio",
      binaryMessenger: controller.binaryMessenger
    )

    audioChannel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "enableBackgroundAudio":
        self?.enableBackgroundAudio()
        result(nil)
      case "disableBackgroundAudio":
        self?.disableBackgroundAudio()
        result(nil)
      case "updateNowPlayingInfo":
        if let args = call.arguments as? [String: Any] {
          self?.updateNowPlayingInfo(args)
        }
        result(nil)
      case "setPlaybackState":
        if let isPlaying = call.arguments as? Bool {
          self?.setPlaybackState(isPlaying: isPlaying)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Setup remote control events (notification center controls)
    setupRemoteControls()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func setupAudioSession() {
    audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession?.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers, .duckOthers])
      try audioSession?.setActive(true)
    } catch {
      print("Failed to set audio session: \(error)")
    }
  }

  func enableBackgroundAudio() {
    do {
      try audioSession?.setActive(true)
    } catch {
      print("Failed to activate audio session: \(error)")
    }
  }

  func disableBackgroundAudio() {
    do {
      try audioSession?.setActive(false)
    } catch {
      print("Failed to deactivate audio session: \(error)")
    }
  }

  func updateNowPlayingInfo(_ info: [String: Any]) {
    var nowPlayingInfo = [String: Any]()

    if let title = info["title"] as? String {
      nowPlayingInfo[MPMediaItemPropertyTitle] = title
    }
    if let artist = info["artist"] as? String {
      nowPlayingInfo[MPMediaItemPropertyArtist] = artist
    }
    if let duration = info["duration"] as? Double {
      nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let currentTime = info["currentTime"] as? Double {
      nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  func setPlaybackState(isPlaying: Bool) {
    let state: MPNowPlayingPlaybackState = isPlaying ? .playing : .paused
    MPNowPlayingInfoCenter.default().playbackState = state
  }

  func setupRemoteControls() {
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.addTarget { [weak self] _ in
      // Tell Flutter to play
      self?.sendCommandToFlutter("play")
      return .success
    }

    commandCenter.pauseCommand.addTarget { [weak self] _ in
      // Tell Flutter to pause
      self?.sendCommandToFlutter("pause")
      return .success
    }

    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.sendCommandToFlutter("toggle")
      return .success
    }

    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
  }

  func sendCommandToFlutter(_ command: String) {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.mrplay/audio",
      binaryMessenger: controller.binaryMessenger
    )
    channel.invokeMethod("remoteControlEvent", arguments: command)
  }

  // Keep audio alive when app enters background
  override func applicationDidEnterBackground(_ application: UIApplication) {
    // Audio session stays active due to .playback category
    // WKWebView audio continues automatically
  }
}
iOS Info.plist Additions:
xml
<!-- ios/Runner/Info.plist -->
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
Flutter Audio Service:
dart
// lib/services/audio_service.dart
import 'package:flutter/services.dart';

class AudioService {
  static const MethodChannel _channel = MethodChannel('com.mrplay/audio');

  static Future<void> enableBackgroundAudio() async {
    await _channel.invokeMethod('enableBackgroundAudio');
  }

  static Future<void> updateNowPlayingInfo({
    required String title,
    required String artist,
    required double duration,
    required double currentTime,
  }) async {
    await _channel.invokeMethod('updateNowPlayingInfo', {
      'title': title,
      'artist': artist,
      'duration': duration,
      'currentTime': currentTime,
    });
  }

  static Future<void> setPlaybackState(bool isPlaying) async {
    await _channel.invokeMethod('setPlaybackState', isPlaying);
  }

  static void setRemoteControlHandler(Function(String) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'remoteControlEvent') {
        handler(call.arguments as String);
      }
    });
  }
}
5. Notification Center Controls
Handled by native iOS code above. The MPRemoteCommandCenter and MPNowPlayingInfoCenter provide:
Play/Pause button in notification center
Lock screen controls
Title/artist display
Playback progress bar
Flutter integration:
dart
// In your WebViewBloc or MiniPlayerBloc:
AudioService.setRemoteControlHandler((command) {
  switch (command) {
    case 'play':
      webViewController.runJavaScript(YouTubeJS.playScript);
      break;
    case 'pause':
      webViewController.runJavaScript(YouTubeJS.pauseScript);
      break;
    case 'toggle':
      // Check current state and toggle
      webViewController.runJavaScript('''
        (function() {
          const video = document.querySelector("video");
          if (video) {
            if (video.paused) video.play(); else video.pause();
          }
        })();
      ''');
      break;
  }
});
6. Search Functionality
Native Flutter search overlay:
Tap search bar → open search page
Search suggestions from platform's search API (or just redirect to platform's search)
For YouTube: use YouTube search API or redirect to m.youtube.com/results?search_query=QUERY
7. Settings Screen
Features:
Dark/Light mode toggle
Default platform selection
Clear cache/history
About / Privacy Policy
Rate app
Share app
8. Favorites/History
Using Hive for local storage:
dart
@HiveType(typeId: 0)
class FavoriteVideo {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final String channel;
  @HiveField(3)
  final String thumbnailUrl;
  @HiveField(4)
  final String platformUrl;
  @HiveField(5)
  final DateTime addedAt;
}
Dependencies (pubspec.yaml)
yaml
name: mrplay
description: Multi-platform video hub with background audio
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6
  webview_flutter: ^4.7.0
  webview_flutter_wkwebview: ^3.12.0
  flutter_bloc: ^8.1.4
  equatable: ^2.0.5
  shared_preferences: ^2.2.2
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  dio: ^5.4.0
  json_annotation: ^4.8.1
  flutter_svg: ^2.0.9
  url_launcher: ^6.2.4
  share_plus: ^7.2.2
  path_provider: ^2.1.2
  google_fonts: ^6.1.0
  shimmer: ^3.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/icons/
    - assets/images/
App Store Compliance Checklist
App Information
App Name: MrPlay
Subtitle: "Your Video Hub"
Description: Focus on multi-platform hub, background audio, mini player. NEVER mention "ad-free" or "no ads".
Keywords: video hub, background audio, mini player, multi platform
Review Notes
plain
This app uses WKWebView to load the official mobile websites of video and content platforms (youtube.com, twitch.tv, instagram.com, etc.). No content is downloaded, cached, or modified. All video playback occurs through the platforms' own web players. The app provides native iOS features including a multi-platform hub, persistent mini player, and background audio controls that are not available in mobile browsers.
Demo Account
Provide test Google account for YouTube testing
Provide test credentials for other platforms if needed
Screenshots
Show Hub screen (colorful platform grid)
Show YouTube loaded in WebView (natural state)
Show Mini Player at bottom
Show Settings screen
Do NOT show any ad-blocking in screenshots
What to Avoid
❌ "Block YouTube ads" in description
❌ "Ad-free YouTube" anywhere
❌ Screenshot showing YouTube without ads (if ads appear naturally, fine)
❌ "Download videos" feature
❌ Network-level ad blocking
Build & Distribution (Codemagic)
Codemagic Configuration
yaml
workflows:
  ios-release:
    name: iOS Release
    instance_type: mac_mini_m1
    environment:
      flutter: stable
      xcode: latest
      cocoapods: default
    cache:
      cache_paths:
        - ~/.pub-cache
        - ~/Library/Caches/CocoaPods
    scripts:
      - name: Flutter doctor
        script: flutter doctor
      - name: Get dependencies
        script: flutter pub get
      - name: Build iOS
        script: flutter build ios --release --no-codesign
      - name: Pod install
        script: cd ios && pod install
      - name: Build archive
        script: |
          cd ios
          xcodebuild archive             -workspace Runner.xcworkspace             -scheme Runner             -archivePath build/Runner.xcarchive
      - name: Export IPA
        script: |
          cd ios
          xcodebuild -exportArchive             -archivePath build/Runner.xcarchive             -exportPath build/Runner.ipa             -exportOptionsPlist ExportOptions.plist
    artifacts:
      - build/Runner.ipa
    publishing:
      app_store_connect:
        api_key: $APP_STORE_CONNECT_KEY
        key_id: $APP_STORE_CONNECT_KEY_ID
        issuer_id: $APP_STORE_CONNECT_ISSUER_ID
Required Environment Variables in Codemagic
APP_STORE_CONNECT_KEY
APP_STORE_CONNECT_KEY_ID
APP_STORE_CONNECT_ISSUER_ID
CERTIFICATE
CERTIFICATE_PASSWORD
PROVISIONING_PROFILE
Known Risks & Mitigations
Table
Risk	Mitigation
YouTube changes DOM structure	Monitor and update JS selectors regularly. Use broad selectors + fallback.
Apple rejects for "minimum functionality"	Ensure multi-platform hub + native mini player + settings are prominent.
Background audio stops on app background	Native AVAudioSession must be configured correctly. Test on real device.
Notification controls don't sync	JS polling interval + native bridging latency. Accept 200-500ms delay.
WebView memory leak	Dispose controllers properly. Use webview_flutter latest version.
App removed after approval	Have backup distribution plan (TestFlight, AltStore).
Development Phases
Phase 1: Foundation (Week 1)
[ ] Flutter project setup
[ ] Hub screen with platform grid
[ ] Basic WebView screen (no JS injection)
[ ] Navigation between Hub and WebView
Phase 2: Core Features (Week 2)
[ ] JavaScript injection for ad blocking
[ ] Persistent WebView architecture
[ ] Mini player widget
[ ] Minimize/expand/close functionality
Phase 3: Native iOS (Week 3)
[ ] AVAudioSession setup
[ ] Background audio entitlement
[ ] Notification center controls
[ ] Remote control event handling
Phase 4: Polish (Week 4)
[ ] Settings screen
[ ] Favorites/history
[ ] Search functionality
[ ] UI polish, animations
[ ] App Store assets
Phase 5: Submission (Week 5)
[ ] Codemagic build pipeline
[ ] TestFlight testing
[ ] App Store submission
[ ] Iterate on rejections
Troubleshooting Guide
"Background audio stops when app closes"
Check Info.plist has UIBackgroundModes → audio
Check AVAudioSession category is .playback
Check audio background mode is enabled in Xcode Signing & Capabilities
Test on physical device (simulator doesn't support background audio properly)
"Mini player doesn't show video info"
Check JavaScript channel is registered: addJavaScriptChannel('videoState', ...)
Check JS injection is running: onPageFinished triggers script injection
Check YouTube DOM selectors are still valid (inspect with Safari Web Inspector)
Add console.log in JS and check Safari console
"Notification controls don't work"
Check MPRemoteCommandCenter targets are set
Check Flutter method channel receives remoteControlEvent
Verify method channel name matches exactly: com.mrplay/audio
Test on physical device (simulator doesn't show remote controls)
"App rejected for minimum functionality"
Add more native features: custom search, favorites, history, settings
Emphasize multi-platform hub in description
Show native mini player prominently in screenshots
Consider adding a native onboarding/tutorial
"YouTube ads still showing"
Check JS injection is executing (add debug alerts)
Update ad selectors in youtube_js.dart
Check if YouTube is using new ad format (check DOM with Safari Inspector)
Consider adding MutationObserver with deeper subtree monitoring
