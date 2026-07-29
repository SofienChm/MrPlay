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
