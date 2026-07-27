import 'package:flutter/services.dart';

class AudioService {
  static const MethodChannel _channel = MethodChannel('com.mrplay/audio');
  static const MethodChannel _webViewChannel = MethodChannel('com.mrplay/webview');

  static Function(String)? _remoteControlHandler;

  static Future<void> enableBackgroundAudio() async {
    await _channel.invokeMethod('enableBackgroundAudio');
  }

  static Future<void> disableBackgroundAudio() async {
    await _channel.invokeMethod('disableBackgroundAudio');
  }

  static Future<void> updateNowPlayingInfo({
    required String title,
    required String artist,
    required double duration,
    required double currentTime,
  }) async {
    await _channel.invokeMethod('updateNowPlayingInfo', {
      'title': title.isNotEmpty ? title : 'MrPlay',
      'artist': artist.isNotEmpty ? artist : 'YouTube',
      'duration': duration > 0 ? duration : 0,
      'currentTime': currentTime > 0 ? currentTime : 0,
    });
  }

  static Future<void> setPlaybackState(bool isPlaying) async {
    await _channel.invokeMethod('setPlaybackState', isPlaying);
  }

  static Future<void> configureWebView() async {
    await _webViewChannel.invokeMethod('configureForPlayback');
  }

  static void setRemoteControlHandler(Function(String) handler) {
    _remoteControlHandler = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'remoteControlEvent') {
        final command = call.arguments as String;
        _remoteControlHandler?.call(command);
      }
    });
  }
}
