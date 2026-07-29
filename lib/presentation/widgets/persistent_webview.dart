import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/constants/youtube_js.dart';
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

class PersistentWebViewState extends State<PersistentWebView> {
  late final WebViewController _controller;
  WebViewState _state = WebViewState.hidden;
  VideoInfo _currentVideo = const VideoInfo();
  String _platformName = '';
  String _currentUrl = '';
  bool _isLoading = false;
  bool _isFavorite = false;
  String _favoriteId = '';

  late Box<String> _historyBox;

  @override
  void initState() {
    super.initState();
    _initHistoryBox();
    _initWebView();
    _setupAudioService();
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
          onPageFinished: (String url) {
            _currentUrl = url;
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
              if (url.contains('youtube.com')) {
                _controller.runJavaScript(YouTubeJS.adBlockScript);
              }
              _addToHistory(url);
            }
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
          _isFavorite = widget.favoritesRepository?.isFavorite(_favoriteId) ?? false;
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

  Future<void> _loadUrl(String url) async {
    setState(() {
      _isLoading = true;
      _state = WebViewState.fullscreen;
      _currentUrl = url;
    });
    await _controller.loadRequest(Uri.parse(url));
  }

  void navigateTo(String url, {String platformName = ''}) {
    _platformName = platformName;
    _loadUrl(url);
  }

  void minimize() {
    setState(() => _state = WebViewState.mini);
  }

  void maximize() {
    setState(() => _state = WebViewState.fullscreen);
  }

  void close() {
    _controller.loadRequest(Uri.parse('about:blank'));
    setState(() {
      _state = WebViewState.hidden;
      _currentVideo = const VideoInfo();
      _isFavorite = false;
      _favoriteId = '';
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
        return MiniPlayerWidget(
          video: _currentVideo,
          onTap: maximize,
          onClose: close,
          controller: _controller,
          isFavorite: _isFavorite,
          onToggleFavorite: _toggleFavorite,
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
                      WebViewWidget(controller: _controller),
                      if (_isLoading && _currentVideo.title.isEmpty)
                        const LoadingIndicator(),
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
