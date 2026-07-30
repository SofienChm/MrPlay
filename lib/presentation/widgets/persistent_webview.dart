import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/constants/youtube_js.dart';
import '../../core/constants/app_constants.dart' show PiPState;
import '../../data/models/video_model.dart';
import '../../data/models/favorite_video.dart';
import '../../data/repositories/favorites_repository.dart';
import '../../services/audio_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/loading_indicator.dart';

enum WebViewState { hidden, mini, fullscreen }

class PersistentWebView extends StatefulWidget {
  final String? initialUrl;
  final FavoritesRepository? favoritesRepository;

  const PersistentWebView({
    super.key,
    this.initialUrl,
    this.favoritesRepository,
  });

  @override
  State<PersistentWebView> createState() => PersistentWebViewState();
}

class PersistentWebViewState extends State<PersistentWebView>
    with SingleTickerProviderStateMixin {
  late final WebViewController _controller;
  WebViewState _state = WebViewState.hidden;
  PiPState _pipState = PiPState.none;
  VideoInfo _currentVideo = const VideoInfo();
  String _platformName = '';
  String _currentUrl = '';
  bool _isLoading = false;
  bool _isFavorite = false;
  String _favoriteId = '';

  late Box<String> _historyBox;
  late AnimationController _pipButtonAnimController;
  late Animation<double> _pipButtonAnim;

  // Track if we've injected the video control script
  bool _videoControlInjected = false;

  @override
  void initState() {
    super.initState();
    _initHistoryBox();
    _initWebView();
    _setupAudioService();

    // PiP button pulse animation
    _pipButtonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pipButtonAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _pipButtonAnimController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pipButtonAnimController.dispose();
    super.dispose();
  }

  Future<void> _initHistoryBox() async {
    _historyBox = await Hive.openBox<String>('history');
  }

  void _setupAudioService() {
    AudioService.enableBackgroundAudio();

    AudioService.setRemoteControlHandler((command) {
      switch (command) {
        case 'play':
          _controller.runJavaScript(YouTubeJS.playScript);
          break;
        case 'pause':
          _controller.runJavaScript(YouTubeJS.pauseScript);
          break;
        case 'toggle':
          _controller.runJavaScript('''
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
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _isLoading = progress < 100;
              });
            }
          },
          onPageStarted: (String url) {
            _currentUrl = url;
            _videoControlInjected = false;
            if (mounted) {
              setState(() {
                _isLoading = true;
              });
            }
          },
          onPageFinished: (String url) {
            _currentUrl = url;
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            // Inject video control script on every page load
            _injectVideoControlScript();
            _addToHistory(url);
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'videoState',
        onMessageReceived: _onVideoState,
      );

    if (widget.initialUrl != null) {
      _loadUrl(widget.initialUrl!);
    }
  }

  Future<void> _injectVideoControlScript() async {
    if (_videoControlInjected) return;
    try {
      await _controller.runJavaScript(YouTubeJS.videoControlScript);
      _videoControlInjected = true;
    } catch (_) {}
  }

  Future<void> _addToHistory(String url) async {
    try {
      final history = {
        'url': url,
        'platformName': _platformName,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _historyBox.add(jsonEncode(history));
    } catch (_) {}
  }

  void _onVideoState(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final video = VideoInfo.fromJson(data);
      if (!mounted) return;
      setState(() {
        _currentVideo = video;
        if (video.title.isNotEmpty) {
          _favoriteId = '${video.title}_${video.channel}'.hashCode.toString();
          _isFavorite =
              widget.favoritesRepository?.isFavorite(_favoriteId) ?? false;
        }
      });

      if (video.title.isNotEmpty) {
        AudioService.updateNowPlayingInfo(
          title: video.title,
          artist: video.channel.isNotEmpty ? video.channel : 'MrPlay',
          duration: video.duration,
          currentTime: video.currentTime,
        );
        AudioService.setPlaybackState(video.isPlaying);
      }
    } catch (_) {}
  }

  void _toggleFavorite() {
    if (_currentVideo.title.isEmpty) return;

    if (_isFavorite) {
      widget.favoritesRepository?.remove(_favoriteId);
      setState(() => _isFavorite = false);
    } else {
      final favorite = FavoriteVideo(
        id: _favoriteId,
        title: _currentVideo.title,
        channel: _currentVideo.channel,
        thumbnailUrl: _currentVideo.thumbnailUrl,
        platformUrl: _currentUrl,
      );
      widget.favoritesRepository?.add(favorite);
      setState(() => _isFavorite = true);
    }
  }

  /// Enter PiP mode: keeps WebView fullscreen for YouTube browsing,
  /// scrolls page down to trigger YouTube's native mini-player.
  Future<void> _enterPiP() async {
    if (_state != WebViewState.fullscreen || _currentVideo.title.isEmpty) return;

    setState(() => _pipState = PiPState.entering);

    try {
      // Inject JS to scroll down (triggers YouTube's own mini-player)
      // and attempt system PiP via iOS WKWebView
      await _controller.runJavaScript(YouTubeJS.enterMiniPlayerScript);
    } catch (_) {}

    // Show a brief feedback that PiP was triggered
    if (mounted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.picture_in_picture_alt, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Video playing in background — browse freely'),
            ],
          ),
          backgroundColor: const Color(0xFF00C853),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _pipState = PiPState.active;
      });
    }
  }

  /// Exit PiP: scroll back to top of the video page
  Future<void> _exitPiP() async {
    try {
      await _controller.runJavaScript(YouTubeJS.exitMiniPlayerScript);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _pipState = PiPState.none;
      });
    }
  }

  /// Force unmute all video elements in the WebView
  Future<void> _forceUnmute() async {
    try {
      await _controller.runJavaScript(YouTubeJS.forceUnmuteScript);
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.volume_up, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Audio unmuted'),
            ],
          ),
          backgroundColor: Color(0xFF00C853),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      );
    }
  }

  Future<void> _loadUrl(String url) async {
    setState(() {
      _isLoading = true;
      _state = WebViewState.fullscreen;
      _pipState = PiPState.none;
      _currentUrl = url;
      _videoControlInjected = false;
    });
    await _controller.loadRequest(Uri.parse(url));
  }

  void navigateTo(String url, {String platformName = ''}) {
    _platformName = platformName;
    _loadUrl(url);
  }

  void minimize() {
    setState(() {
      _state = WebViewState.mini;
      _pipState = PiPState.none;
    });
  }

  void maximize() {
    setState(() {
      _state = WebViewState.fullscreen;
      _pipState = PiPState.none;
    });
  }

  void close() {
    _controller.loadRequest(Uri.parse('about:blank'));
    setState(() {
      _state = WebViewState.hidden;
      _currentVideo = const VideoInfo();
      _isFavorite = false;
      _favoriteId = '';
      _pipState = PiPState.none;
    });
  }

  Future<void> goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
  }

  Future<void> goForward() async {
    if (await _controller.canGoForward()) {
      await _controller.goForward();
    }
  }

  void reload() {
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      child: _buildCurrentState(),
    );
  }

  Widget _buildCurrentState() {
    switch (_state) {
      case WebViewState.hidden:
        return const SizedBox.shrink();

      case WebViewState.mini:
        return Column(
          children: [
            const Spacer(),
            MiniPlayerWidget(
              video: _currentVideo,
              onTap: maximize,
              onClose: close,
              controller: _controller,
              isFavorite: _isFavorite,
              onToggleFavorite: _toggleFavorite,
              pipState: _pipState,
              onPiPToggle: (_pipState == PiPState.active) ? _exitPiP : null,
            ),
          ],
        );

      case WebViewState.fullscreen:
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: SafeArea(
            child: Column(
              children: [
                _buildToolbar(),
                if (_isLoading)
                  const LinearProgressIndicator(
                    backgroundColor: Color(0xFF2C2C2C),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF00C853),
                    ),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      // WebView with swipe-down gesture for PiP
                      GestureDetector(
                        onVerticalDragEnd: (details) {
                          // High velocity threshold to avoid conflicting
                          // with YouTube scroll — only trigger on fast fling
                          if (details.primaryVelocity != null &&
                              details.primaryVelocity! > 1200 &&
                              _currentVideo.title.isNotEmpty) {
                            _enterPiP();
                          }
                        },
                        child: WebViewWidget(controller: _controller),
                      ),
                      if (_isLoading && _currentVideo.title.isEmpty)
                        const LoadingIndicator(),

                      // ── Floating PiP button (bottom-right, ~56px circle) ──
                      if (_currentVideo.title.isNotEmpty &&
                          _pipState != PiPState.active)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: AnimatedBuilder(
                            animation: _pipButtonAnim,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _pipButtonAnim.value,
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF00C853),
                                        Color(0xFF009624),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF00C853)
                                            .withValues(alpha: 0.4),
                                        blurRadius: 12,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: _enterPiP,
                                      child: const Icon(
                                        Icons.keyboard_double_arrow_down,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                      // ── PiP active indicator (subtle badge) ──
                      if (_pipState == PiPState.active)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00C853)
                                  .withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.keyboard_double_arrow_down,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'PiP',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade800),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: goBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'Back',
          ),
          IconButton(
            onPressed: goForward,
            icon: const Icon(Icons.arrow_forward, color: Colors.white),
            tooltip: 'Forward',
          ),
          // Unmute button
          IconButton(
            onPressed: _forceUnmute,
            icon: const Icon(Icons.volume_up, color: Colors.white),
            tooltip: 'Unmute',
          ),
          Expanded(
            child: GestureDetector(
              onTap: minimize,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _platformName.isNotEmpty ? _platformName : 'WebView',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_currentVideo.title.isNotEmpty)
                    Text(
                      _currentVideo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
          // PiP button in toolbar
          if (_currentVideo.title.isNotEmpty)
            IconButton(
              onPressed: _enterPiP,
              icon: Icon(
                Icons.picture_in_picture_alt,
                color: _pipState == PiPState.active
                    ? const Color(0xFF00C853)
                    : Colors.white,
              ),
              tooltip: 'Picture in Picture',
            ),
          IconButton(
            onPressed: minimize,
            icon: const Icon(Icons.minimize, color: Colors.white),
            tooltip: 'Minimize',
          ),
          IconButton(
            onPressed: close,
            icon: const Icon(Icons.close, color: Colors.white54),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}
