import 'package:flutter/services.dart';

class AudioService {
  static const MethodChannel _channel = MethodChannel('com.mrplay/audio');

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
    _remoteControlHandler = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'remoteControlEvent') {
        final command = call.arguments as String;
        _remoteControlHandler?.call(command);
      }
    });
  }
}
