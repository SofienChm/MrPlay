import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

/// Silent audio loop used to keep iOS WebView audio alive in the background.
///
/// On Android this is intentionally a no-op: the foreground service
/// (`PlaybackService`) keeps the app process alive and
/// `allowBackgroundAudioPlaying` keeps the WebView's audio going. A second
/// audio player (ExoPlayer) would create a competing MediaSession and audio
/// focus requests, which causes the video to pause and the app to jank after
/// returning from the background.
class BackgroundAudioKeepAlive {
  BackgroundAudioKeepAlive._();

  static final BackgroundAudioKeepAlive instance = BackgroundAudioKeepAlive._();

  final AudioPlayer _player = AudioPlayer();
  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    if (Platform.isAndroid) return;
    _running = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0);
      await _player.play(AssetSource('audio/silence.wav'));
    } catch (_) {
      _running = false;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _player.stop();
    } catch (_) {}
  }
}
