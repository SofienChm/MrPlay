import 'package:audioplayers/audioplayers.dart';

import '../core/utils/log.dart';

/// Silent looping audio that keeps the AVAudioSession producing sound so iOS
/// does not suspend the app (and WebKit) in the background.
///
/// [start]/[stop] are race-safe: a stop that lands while a start is awaiting
/// `play()` invalidates it through a generation counter, so the loop is never
/// left running after [stop]. If the loop dies on its own, the next [start]
/// brings it back.
class KeepAliveAudio {
  KeepAliveAudio({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _player.onPlayerStateChanged.listen((state) {
      if (_running &&
          (state == PlayerState.stopped || state == PlayerState.completed || state == PlayerState.disposed)) {
        _running = false;
        log('keep-alive stopped unexpectedly: $state');
      }
    });
  }

  final AudioPlayer _player;
  bool _running = false;
  int _generation = 0;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    final generation = _generation;
    _running = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0);
      await _player.play(AssetSource('audio/silence.wav'));
      if (generation != _generation && !_running) await _player.stop();
    } on Exception catch (e) {
      log('keep-alive start failed: $e');
      if (generation == _generation) _running = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    if (!_running) return;
    _running = false;
    try {
      await _player.stop();
    } on Exception catch (e) {
      log('keep-alive stop failed: $e');
    }
  }
}
