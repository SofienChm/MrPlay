import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:audio_session/audio_session.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../theme/app_colors.dart';
import '../services/js_snippets.dart';
import '../services/media_manager.dart';
import '../widgets/unified_banner_ad_slot.dart';
import '../widgets/mini_player_widget.dart';
import '../widgets/control_bar_button.dart';
import '../widgets/search_bar_widget.dart';
import '../screens/search_overlay_widget.dart';
import '../utils/navigation_utils.dart';

class BrowserScreen extends StatefulWidget {
  final String targetUrl;
  final VoidCallback? onClose;

  const BrowserScreen({
    super.key,
    required this.targetUrl,
    this.onClose,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with WidgetsBindingObserver {
  static const _bgChannel = MethodChannel('com.mrplay/background_playback');

  static const double _miniPlayerHeight = 72.0;
  static const double _bannerSlotHeight = 60.0;

  final _searchController = TextEditingController();

  InAppWebViewController? _webViewController;
  InAppWebViewController? _bgWebViewController;
  bool _isOnWatchPage = false;
  bool _isMiniPlayerOpen = false;
  bool _isSearchFocused = false;
  bool _isKeyboardOpen = false;
  bool _isInPip = false;
  bool _showSearchBar = false;
  String _cachedUrl = '';

  bool _isPlayingInBackground = false;
  bool _isPlayingNative = false;
  bool _showMiniPlayer = false;
  bool _isBgWebViewEnabled = false;
  String _miniPlayerTitle = '';
  String _bgWatchUrl = '';

  List<Video> _searchResults = [];
  bool _showSearchResults = false;
  bool _isSearchLoading = false;

  List<String> _suggestions = [];
  bool _showSuggestions = false;
  Timer? _suggestionsTimer;
  late final YoutubeExplode _youtube;

  @override
  void initState() {
    super.initState();
    _youtube = YoutubeExplode();
    WidgetsBinding.instance.addObserver(this);
    _initAudioSession();
    _bgChannel.setMethodCallHandler((call) async {
      if (call.method == 'pipModeChanged') {
        if (!mounted) return;
        setState(() => _isInPip = call.arguments as bool);
      } else if (call.method == 'pauseFromNative') {
        await _webViewController?.evaluateJavascript(source: JsSnippets.pauseVideo);
        if (_bgWebViewController != null) {
          try { await _bgWebViewController!.evaluateJavascript(source: JsSnippets.pauseVideo); } catch (_) {}
        }
      } else if (call.method == 'resumeFromNative') {
        await _webViewController?.evaluateJavascript(source: JsSnippets.resumeVideo);
        _injectVisibilitySpoof();
        if (_bgWebViewController != null) {
          try {
            await _bgWebViewController!.evaluateJavascript(source: 'window.__mrplayBgInjected = false; window.__mrplayUserPaused = false;');
            await _bgWebViewController!.evaluateJavascript(source: JsSnippets.bgWebViewInject);
          } catch (_) {}
        }
      }
    });
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
    } catch (e) {
      debugPrint('[MrPlay] AudioSession error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _suggestionsTimer?.cancel();
    _searchController.dispose();
    _bgChannel.setMethodCallHandler(null);
    _stopBackgroundService();
    MediaManager.instance.stop();
    _cleanupJsIntervals();
    _youtube.close();
    super.dispose();
  }

  Future<void> _cleanupJsIntervals() async {
    await _webViewController?.evaluateJavascript(
      source: JsSnippets.cleanupIntervals,
    );
    if (_bgWebViewController != null) {
      try {
        await _bgWebViewController!.evaluateJavascript(
          source: JsSnippets.cleanupBgInterval,
        );
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isPlayingNative) return;

    if (state == AppLifecycleState.inactive) {
      _webViewController?.resumeTimers();
      if (_isOnWatchPage && !_isPlayingInBackground) {
        _startBackgroundIfPlaying();
      }
      return;
    }

    if (state == AppLifecycleState.paused) {
      // no-op
    } else if (state == AppLifecycleState.resumed) {
      _webViewController?.resumeTimers();
      if (_isPlayingInBackground) {
        _isPlayingInBackground = false;
        _bgChannel.invokeMethod('stopForegroundService');
        _restoreVisibility();
        _syncPauseState();
        debugPrint('⏹️ Background playback stopped');
      }
    }
  }

  Future<void> _startBackgroundIfPlaying() async {
    final wasPaused = await _bgChannel.invokeMethod('wasPaused');
    if (wasPaused == true) return;
    final isPlaying = await _isVideoPlaying();
    if (!isPlaying) return;
    _isPlayingInBackground = true;
    _bgChannel.invokeMethod('startForegroundService', {'title': 'MrPlay Audio'});
    _injectVisibilitySpoof();
    _webViewController?.evaluateJavascript(source: JsSnippets.audioPauseBlocker);
    final title = await _getVideoTitle();
    if (title.isNotEmpty) {
      _bgChannel.invokeMethod('startForegroundService', {'title': title});
    }
    _updateNowPlaying(title);
    debugPrint('▶️ Background playback started');
  }

  Future<bool> _isVideoPlaying() async {
    try {
      final result = await _webViewController?.evaluateJavascript(
        source: '(function(){var v=document.querySelector("video");return v?!v.paused:false;})()',
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  void _updateNowPlaying(String title) {
    _bgChannel.invokeMethod('updateNowPlaying', {'title': title});
  }

  Future<void> _syncPauseState() async {
    try {
      final wasPaused = await _bgChannel.invokeMethod('wasPaused');
      if (wasPaused == true) {
        await _webViewController?.evaluateJavascript(source: JsSnippets.pauseVideo);
        await _bgChannel.invokeMethod('clearPaused');
      }
    } catch (_) {}
  }

  Future<void> _stopBackgroundService() async {
    await _bgChannel.invokeMethod('stopForegroundService');
  }

  // ── JavaScript injections ────────────────────────────────────────────────

  Future<void> _injectKeepAliveVisibilitySpoof({InAppWebViewController? controller}) async {
    final ctrl = controller ?? _webViewController;
    await ctrl?.evaluateJavascript(
      source: JsSnippets.keepAliveVisibilitySpoof,
    );
  }

  Future<void> _injectUnmuteVideo() async {
    await _webViewController?.evaluateJavascript(
      source: JsSnippets.unmuteVideo,
    );
  }

  Future<void> _injectVisibilitySpoof() async {
    await _webViewController?.evaluateJavascript(
      source: JsSnippets.visibilitySpoof,
    );
  }

  Future<void> _restoreVisibility() async {
    await _webViewController?.evaluateJavascript(
      source: JsSnippets.restoreVisibility,
    );
  }

  Future<void> _injectCleanLayoutCss() async {
    await _webViewController?.evaluateJavascript(
      source: JsSnippets.cleanLayoutCss,
    );
  }

  Future<void> _injectSearchFocusMonitor() async {
    await _webViewController?.evaluateJavascript(
      source: JsSnippets.searchFocusMonitor,
    );
  }

  Future<void> _injectKeyboardMonitor() async {
    await _webViewController?.evaluateJavascript(
      source: JsSnippets.keyboardMonitor,
    );
  }

  Future<void> _injectMiniPlayerMonitor() async {
    await _webViewController?.evaluateJavascript(
      source: JsSnippets.miniPlayerMonitor,
    );
  }

  Future<void> _checkNavigationState() async {
    final url = (await _webViewController?.getUrl())?.toString() ?? '';
    if (!mounted) return;
    setState(() {
      _isOnWatchPage = url.contains('/watch');
      _cachedUrl = url;
    });
  }

  Future<String> _getVideoTitle() async {
    try {
      final r = await _webViewController?.evaluateJavascript(
        source: JsSnippets.getVideoTitle,
      );
      if (r is String && r.isNotEmpty) return r;
    } catch (e) {
      debugPrint('[MrPlay] getVideoTitle error: $e');
    }
    return 'MrPlay Audio';
  }

  // ── Mini-player / PiP handlers ────────────────────────────────────────

  Future<void> _handleMinimize({bool triggerPip = false}) async {
    final title = await _getVideoTitle();
    final currentUrl = (await _webViewController?.getUrl())?.toString() ?? '';
    if (!mounted) return;

    setState(() {
      _showMiniPlayer = true;
      _miniPlayerTitle = title;
      _bgWatchUrl = currentUrl;
    });

    if (Platform.isIOS) {
      // iOS: background WebView works fine — no audio focus conflict
      setState(() => _isBgWebViewEnabled = true);
      await Future.delayed(const Duration(milliseconds: 500));

      if (triggerPip) {
        try {
          await _webViewController?.evaluateJavascript(
            source: JsSnippets.triggerPip,
          );
        } catch (e) {
          debugPrint('[MrPlay] iOS PiP injection failed: $e');
        }
        await Future.delayed(const Duration(seconds: 1));
      }

      _isPlayingInBackground = true;
      _bgChannel.invokeMethod('startForegroundService', {'title': title});

      if (await _webViewController?.canGoBack() == true) {
        await _webViewController?.goBack();
      } else {
        await _webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri('https://m.youtube.com/')),
        );
      }
    } else {
      // Android: keep main WebView on watch page — NO background WebView.
      // Dual WebViews on Android cause audio focus conflict + GPU overload.
      // Audio continues naturally in the main WebView.
      // User browses via the Flutter-native search overlay.
      _isPlayingInBackground = true;
      _bgChannel.invokeMethod('startForegroundService', {'title': title});
    }
  }

  void _handleExpandMiniPlayer() {
    final watchUrl = _bgWatchUrl;
    setState(() {
      _showMiniPlayer = false;
      _isBgWebViewEnabled = false;
      _showSearchResults = false;
      _searchResults = [];
    });
    if (watchUrl.isNotEmpty) {
      _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(watchUrl)),
      );
    }
  }

  void _handleCloseMiniPlayer() {
    _isPlayingInBackground = false;
    _isPlayingNative = false;
    _bgWatchUrl = '';
    _bgChannel.invokeMethod('stopForegroundService');
    MediaManager.instance.stop();
    if (_bgWebViewController != null) {
      try {
        _bgWebViewController!.dispose();
      } catch (e) {
        debugPrint('[MrPlay] bg WebView dispose error: $e');
      }
      _bgWebViewController = null;
    }
    setState(() {
      _showMiniPlayer = false;
      _isBgWebViewEnabled = false;
    });
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('https://m.youtube.com/')),
    );
  }

  void _focusSearch() {
    final opening = !_showSearchBar;
    setState(() {
      _showSearchBar = opening;
      if (!opening) {
        _showSuggestions = false;
        _suggestions = [];
      }
    });
    if (opening) {
      _searchController.clear();
    }
  }

  Future<void> _handleSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _showSearchBar = false;
      _showSearchResults = true;
      _isSearchLoading = true;
    });

    try {
      final results = await _youtube.search.search(trimmed);
      if (!mounted) return;
      setState(() {
        _searchResults = results.toList();
        _isSearchLoading = false;
      });
    } catch (e) {
      debugPrint('[MrPlay] Search error: $e');
      if (!mounted) return;
      setState(() => _isSearchLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _suggestionsTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _showSuggestions = false;
        _suggestions = [];
      });
      return;
    }
    _suggestionsTimer = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions(query.trim());
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    try {
      final results = await _youtube.search.getQuerySuggestions(query);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _showSuggestions = results.isNotEmpty;
      });
    } catch (e) {
      debugPrint('[MrPlay] Suggestions error: $e');
    }
  }

  void _handleSuggestionTap(String suggestion) {
    _searchController.text = suggestion;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.length),
    );
    setState(() => _showSuggestions = false);
    _handleSearch(suggestion);
  }

  void _handleSearchResultTap(Video video) {
    setState(() => _showSearchResults = false);
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(video.url)),
    );
  }

  void _handleDismissSearch() {
    setState(() {
      _showSearchResults = false;
      _searchResults = [];
    });
  }

  void _showOptionsSheet() {
    showModalBottomSheet(
      context: context,
                  backgroundColor: AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 32, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDim,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.refresh, color: AppColors.textSecondary),
                title: const Text('Refresh', style: TextStyle(color: Colors.white)),
                onTap: () {
                  _webViewController?.reload();
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: AppColors.textSecondary),
                title: const Text('Copy URL', style: TextStyle(color: Colors.white)),
                onTap: () {
                  _copyCurrentUrl();
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline, color: AppColors.textSecondary),
                title: const Text('Video Info', style: TextStyle(color: Colors.white)),
                onTap: () {
                  _showVideoInfo();
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _copyCurrentUrl() async {
    final url = (await _webViewController?.getUrl())?.toString() ?? _cachedUrl;
    if (url.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('URL copied'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _showVideoInfo() async {
    final title = await _getVideoTitle();
    final url = (await _webViewController?.getUrl())?.toString() ?? '';
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('Now Playing', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.isNotEmpty ? title : 'Unknown',
                style: const TextStyle(color: AppColors.textSecondary)),
            if (url.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(url, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  InAppWebViewSettings get _webViewSettings => InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        allowsPictureInPictureMediaPlayback: true,
        automaticallyAdjustsScrollIndicatorInsets: true,
        javaScriptCanOpenWindowsAutomatically: true,
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        supportZoom: false,
        cacheEnabled: true,
        incognito: false,
        safeBrowsingEnabled: false,
        allowBackgroundAudioPlaying: true,
        useHybridComposition: true,
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final webViewBottomPadding =
        bottomInset + _bannerSlotHeight + (_showMiniPlayer ? _miniPlayerHeight : 0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await NavigationUtils.handleBackNavigation(
          context: context,
          webViewController: _webViewController,
          isOnWatchPage: _isOnWatchPage,
          isMiniPlayerOpen: _isMiniPlayerOpen,
          showMiniPlayer: _showMiniPlayer,
          onCloseMiniPlayer: () => setState(() => _showMiniPlayer = false),
          onClose: () => widget.onClose?.call(),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Background WebView — iOS only (Android keeps main WebView on watch page)
            if (_showMiniPlayer && _isBgWebViewEnabled && Platform.isIOS)
              SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: IgnorePointer(
                  ignoring: true,
                  child: InAppWebView(
                  initialData: InAppWebViewInitialData(data: '<html><body></body></html>'),
                  initialSettings: _webViewSettings,
                  onWebViewCreated: _onBgWebViewCreated,
                  onLoadStop: (controller, url) async {
                    // Only inject on actual watch pages
                    if (!url.toString().contains('/watch')) return;
                    await controller.evaluateJavascript(
                      source: JsSnippets.bgWebViewInject,
                    );
                    await controller.evaluateJavascript(
                      source: JsSnippets.audioPauseBlocker,
                    );
                  },
                ),
              ),
            ),

            // Main WebView (interactive, full screen)
            IgnorePointer(
              ignoring: _showMiniPlayer,
              child: SafeArea(
              top: true,
              bottom: false,
              child: Padding(
              padding: EdgeInsets.only(bottom: webViewBottomPadding),
              child: InAppWebView(
                initialUrlRequest:
                    URLRequest(url: WebUri(widget.targetUrl)),
                initialSettings: _webViewSettings,
                onWebViewCreated: _onWebViewCreated,
                onUpdateVisitedHistory: (controller, url, isReload) async {
                  await _checkNavigationState();
                },
                onLoadStop: (controller, url) async {
                  await _checkNavigationState();
                  await _injectCleanLayoutCss();
                  await _injectSearchFocusMonitor();
                  await _injectMiniPlayerMonitor();
                  await _injectKeyboardMonitor();
                  await _injectKeepAliveVisibilitySpoof();
                  await _injectUnmuteVideo();
                },
                onReceivedError: (controller, request, error) {
                  debugPrint('❌ WebView error: ${error.description}');
                },
                onConsoleMessage: (controller, msg) {
                  if (kDebugMode) {
                    debugPrint('[WebView] ${msg.message}');
                  }
                },
              ),
              ),
              ),
            ),

            // Custom search bar (top area)
            if (_showSearchBar)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                right: 12,
                child: SearchBarWidget(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onSearch: (value) {
                    setState(() => _showSuggestions = false);
                    _handleSearch(value);
                  },
                  suggestions: _suggestions,
                  showSuggestions: _showSuggestions,
                  onSuggestionTap: _handleSuggestionTap,
                ),
              ),

            // Control bar (bottom-right, individually rounded btns)
            if (_isOnWatchPage && !_showMiniPlayer && !_isMiniPlayerOpen && !_isInPip)
              Positioned(
                bottom: 80,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ControlBarButton(
                      icon: Icons.picture_in_picture_alt,
                      tooltip: 'Picture-in-Picture',
                      onPressed: () => _handleMinimize(triggerPip: true),
                    ),
                    const SizedBox(height: 2),
                    ControlBarButton(
                      icon: Icons.search,
                      tooltip: 'Search',
                      onPressed: _focusSearch,
                    ),
                    const SizedBox(height: 2),
                    ControlBarButton(
                      icon: Icons.more_vert,
                      tooltip: 'More',
                      onPressed: _showOptionsSheet,
                    ),
                    const SizedBox(height: 2),
                    ControlBarButton(
                      icon: Icons.keyboard_arrow_down,
                      tooltip: 'Mini-Player',
                      onPressed: () => _handleMinimize(triggerPip: false),
                    ),
                  ],
                ),
              ),

            // MiniPlayer (above BannerAd)
            if (_showMiniPlayer)
              Positioned(
                bottom: bottomInset + _bannerSlotHeight,
                left: 0,
                right: 0,
                child: MiniPlayerWidget(
                  title: _miniPlayerTitle,
                  subtitle: 'Now Playing',
                  onExpand: _handleExpandMiniPlayer,
                  onClose: _handleCloseMiniPlayer,
                ),
              ),

            // Search results overlay
            if (_showSearchResults)
              Positioned.fill(
                child: SearchOverlayWidget(
                  isSearchLoading: _isSearchLoading,
                  searchResults: _searchResults,
                  onDismiss: _handleDismissSearch,
                  onResultTap: _handleSearchResultTap,
                ),
              ),

            // BannerAd (pinned to bottom inside safe area)
            Positioned(
              bottom: bottomInset,
              left: 0,
              right: 0,
              child: UnifiedBannerAdSlot(
                isVisible: !_isSearchFocused && !_isKeyboardOpen && !_isInPip,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
    controller.addJavaScriptHandler(
      handlerName: 'searchFocusChanged',
      callback: (args) {
        if (!mounted) return;
        setState(() => _isSearchFocused = args[0] as bool);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'miniPlayerStateChanged',
      callback: (args) {
        if (!mounted) return;
        setState(() => _isMiniPlayerOpen = args[0] as bool);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'keyboardOpenChanged',
      callback: (args) {
        if (!mounted) return;
        setState(() => _isKeyboardOpen = args[0] as bool);
      },
    );
  }

  void _onBgWebViewCreated(InAppWebViewController controller) {
    _bgWebViewController = controller;
    // Load the watch URL into the background WebView
    if (_bgWatchUrl.isNotEmpty) {
      controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(_bgWatchUrl)),
      );
    }
  }
}


