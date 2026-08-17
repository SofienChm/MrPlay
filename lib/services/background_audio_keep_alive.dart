import 'package:audioplayers/audioplayers.dart';

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
