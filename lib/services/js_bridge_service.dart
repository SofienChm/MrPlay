import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/constants/youtube_js.dart';
import '../data/models/video_model.dart';

typedef VideoStateCallback = void Function(VideoInfo video);

class JsBridgeService {
  final WebViewController controller;
  VideoStateCallback? onVideoStateChanged;

  JsBridgeService({required this.controller, this.onVideoStateChanged}) {
    _setupJavaScriptChannel();
  }

  void _setupJavaScriptChannel() {
    controller.addJavaScriptChannel(
      'videoState',
      onMessageReceived: (JavaScriptMessage message) {
        try {
          final data = jsonDecode(message.message) as Map<String, dynamic>;
          final video = VideoInfo.fromJson(data);
          onVideoStateChanged?.call(video);
        } catch (e) {
          // Silently handle malformed messages
        }
      },
    );
  }

  Future<void> injectYouTubeAdBlock() async {
    await controller.runJavaScript(YouTubeJS.videoControlScript);
  }

  Future<void> pause() async {
    await controller.runJavaScript(YouTubeJS.pauseScript);
  }

  Future<void> play() async {
    await controller.runJavaScript(YouTubeJS.playScript);
  }

  Future<void> seek(double time) async {
    final script = YouTubeJS.seekScript.replaceFirst('%s', time.toString());
    await controller.runJavaScript(script);
  }

  Future<void> loadUrl(String url) async {
    await controller.loadRequest(Uri.parse(url));
  }

  void dispose() {
    onVideoStateChanged = null;
  }
}
