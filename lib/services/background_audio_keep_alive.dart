import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Silent audio loop used to keep iOS WebView audio alive in the background.
///
/// A second, silent `AVAudioPlayer` keeps the `AVAudioSession` actively
/// producing audio, so iOS does not suspend the app (and WebKit) when it
/// backgrounds. Played at volume 0 so the user never hears it. Only used for
/// YouTube Music (audio-only playback); other platforms rely on phantom-PiP.
class BackgroundAudioKeepAlive {
  BackgroundAudioKeepAlive._();

  static final BackgroundAudioKeepAlive instance = BackgroundAudioKeepAlive._();

  final AudioPlayer _player = AudioPlayer();
  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0);
      await _player.play(AssetSource('audio/silence.wav'));
    } catch (e) {
      debugPrint('[MrPlay] background keep-alive start failed: $e');
      _running = false;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[MrPlay] background keep-alive stop failed: $e');
    }
  }
}
