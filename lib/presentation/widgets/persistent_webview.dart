import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/constants/youtube_js.dart';
import '../../models/video.dart';
import '../../providers/player_provider.dart';

class PersistentWebView extends ConsumerStatefulWidget {
  const PersistentWebView({super.key});

  @override
  ConsumerState<PersistentWebView> createState() => PersistentWebViewState();
}

class PersistentWebViewState extends ConsumerState<PersistentWebView> {
  late final WebViewController controller;
  bool isReady = false;
  bool _isLoading = false;
  Timer? _loadingTimer;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  void _initWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() => _isLoading = true);
            }
            _loadingTimer?.cancel();
            _loadingTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() => _isLoading = false);
              }
            });
          },
          onPageFinished: (String url) {
            _loadingTimer?.cancel();
            if (mounted) {
              setState(() => _isLoading = false);
            }
            _onPageLoaded(url);
          },
        ),
      )
      ..addJavaScriptChannel('playerInfo', onMessageReceived: _onPlayerInfo);
  }

  void _onPageLoaded(String url) {
    if (url.contains('youtube.com')) {
      controller.runJavaScript(YouTubeJS.adBlockScript);

      if (url.contains('/watch')) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          controller.runJavaScript('''
            (function() {
              var titleEl = document.querySelector('h1.title, .slim-video-information-title, .ytp-title, #title h1');
              var thumbEl = document.querySelector('.ytp-cued-thumbnail-overlay-image, .html5-main-video');
              var videoId = window.location.search.match(/[?&]v=([^&]+)/);
              var thumbUrl = '';
              if (videoId) {
                thumbUrl = 'https://i.ytimg.com/vi/' + videoId[1] + '/hqdefault.jpg';
              } else if (thumbEl) {
                var bg = thumbEl.style.backgroundImage;
                if (bg) {
                  var match = bg.match(/url\\("?(.+?)"?\\)/);
                  if (match) thumbUrl = match[1];
                }
              }
              var title = titleEl ? titleEl.textContent.trim().substring(0, 200) : '';
              if (title && window.playerInfo && window.playerInfo.postMessage) {
                window.playerInfo.postMessage(JSON.stringify({
                  id: videoId ? videoId[1] : '',
                  title: title,
                  thumbnailUrl: thumbUrl,
                  videoUrl: window.location.href,
                  platform: 'YouTube'
                }));
              }
            })();
          ''');
        });
      }
    }
  }

  void _onPlayerInfo(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final title = data['title'] as String? ?? '';
      if (title.isNotEmpty) {
        final video = Video(
          id: data['id'] ?? '',
          title: title,
          thumbnailUrl: data['thumbnailUrl'] ?? '',
          videoUrl: data['videoUrl'] ?? '',
          platform: data['platform'] ?? 'YouTube',
        );
        // TODO: Replace WebView playback with native video_player in Phase 2
        final currentId = ref.read(playerProvider).currentVideo?.id;
        if (currentId != video.id) {
          ref.read(playerProvider.notifier).play(video);
        }
      }
    } catch (_) {}
  }

  void loadUrl(String url) {
    _loadingTimer?.cancel();
    controller.loadRequest(Uri.parse(url));
    setState(() {
      isReady = true;
      _isLoading = true;
    });
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  Widget _buildFullWebView() {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: WebViewWidget(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isReady) return const SizedBox.shrink();

    return SizedBox(
      height: MediaQuery.of(context).size.height,
      width: double.infinity,
      child: Stack(
        children: [
          _buildFullWebView(),
          if (_isLoading)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
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
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: GestureDetector(
              onTap: () {
                controller.loadRequest(Uri.parse('about:blank'));
                setState(() {
                  isReady = false;
                  _isLoading = false;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
