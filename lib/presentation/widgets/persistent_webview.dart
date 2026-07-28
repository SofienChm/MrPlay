import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/constants/youtube_js.dart';
import '../../data/models/video_model.dart';
import '../../services/audio_service.dart';
import 'mini_player.dart';

class PersistentWebView extends StatefulWidget {
  const PersistentWebView({super.key});

  @override
  State<PersistentWebView> createState() => PersistentWebViewState();
}

class PersistentWebViewState extends State<PersistentWebView> {
  late final WebViewController controller;
  bool isMini = false;
  bool isReady = false;
  VideoInfo? currentVideo;
  Timer? _videoStateTimer;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _initRemoteControls();
  }

  @override
  void dispose() {
    _videoStateTimer?.cancel();
    super.dispose();
  }

  void _initWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            _injectYouTubeScripts(url);
          },
        ),
      )
      ..addJavaScriptChannel(
        'videoState',
        onMessageReceived: _onVideoState,
      );
  }

  void _injectYouTubeScripts(String url) {
    if (!url.contains('youtube.com')) return;

    Future.delayed(const Duration(milliseconds: 300), () {
      controller.runJavaScript(YouTubeJS.adBlockScript);
      controller.runJavaScript(YouTubeJS.backgroundAudioScript);
    });

    _videoStateTimer?.cancel();
    _videoStateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      controller.runJavaScript('''
        (function() {
          if (window.videoState && window.videoState.postMessage) {
            var video = document.querySelector('video');
            if (video) {
              var titleEl = document.querySelector('h1.title, .slim-video-information-title, .ytp-title, #title h1');
              var channelEl = document.querySelector('.ytd-channel-name a, .slim-owner-channel-name a, #text a');
              var thumbEl = document.querySelector('.ytp-cued-thumbnail-overlay-image, .html5-main-video');
              window.videoState.postMessage(JSON.stringify({
                isPlaying: !video.paused,
                currentTime: video.currentTime || 0,
                duration: video.duration || 0,
                title: titleEl ? titleEl.textContent.trim().substring(0, 100) : '',
                channel: channelEl ? channelEl.textContent.trim().substring(0, 100) : '',
                thumbnail: thumbEl ? (thumbEl.style.backgroundImage || '') : ''
              }));
            }
          }
        })();
      ''');
    });
  }

  void _initRemoteControls() {
    AudioService.setRemoteControlHandler((command) {
      switch (command) {
        case 'play':
          controller.runJavaScript(YouTubeJS.playScript);
          break;
        case 'pause':
          controller.runJavaScript(YouTubeJS.pauseScript);
          break;
        case 'toggle':
          controller.runJavaScript(YouTubeJS.toggleScript);
          break;
      }
    });
  }

  void _onVideoState(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message);
      if (mounted) {
        setState(() {
          currentVideo = VideoInfo.fromJson(data);
        });
        AudioService.setPlaybackState(data['isPlaying'] ?? false);
        AudioService.updateNowPlayingInfo(
          title: data['title'] ?? '',
          artist: data['channel'] ?? '',
          duration: (data['duration'] ?? 0).toDouble(),
          currentTime: (data['currentTime'] ?? 0).toDouble(),
        );
      }
    } catch (_) {}
  }

  void loadUrl(String url) {
    _videoStateTimer?.cancel();
    controller.loadRequest(Uri.parse(url));
    setState(() {
      isReady = true;
    });
  }

  void minimize() => setState(() => isMini = true);

  void maximize() => setState(() => isMini = false);

  void close() {
    _videoStateTimer?.cancel();
    controller.loadRequest(Uri.parse('about:blank'));
    setState(() {
      isMini = false;
      isReady = false;
      currentVideo = null;
    });
  }

  void _togglePlayPause() {
    if (currentVideo == null) return;
    final js = currentVideo!.isPlaying
        ? YouTubeJS.pauseScript
        : YouTubeJS.playScript;
    controller.runJavaScript(js);
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
      height: isMini ? 70 : MediaQuery.of(context).size.height,
      width: double.infinity,
      child: Stack(
        children: [
          Opacity(
            opacity: isMini ? 0.0 : 1.0,
            child: IgnorePointer(
              ignoring: isMini,
              child: SizedBox(
                height: isMini ? 0 : MediaQuery.of(context).size.height,
                child: _buildFullWebView(),
              ),
            ),
          ),
          if (!isMini)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 10,
              child: GestureDetector(
                onTap: minimize,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 28),
                ),
              ),
            ),
          if (isMini && currentVideo != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MiniPlayerWidget(
                video: currentVideo!,
                onMaximize: maximize,
                onClose: close,
                onPlayPause: _togglePlayPause,
              ),
            ),
        ],
      ),
    );
  }
}
