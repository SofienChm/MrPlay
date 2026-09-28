import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Silent audio loop used to keep iOS WebView audio alive in the background.
///
/// A second, silent `AVAudioPlayer` keeps the `AVAudioSession` actively
/// producing audio, so iOS does not suspend the app (and WebKit) when it
/// backgrounds. Played at volume 0 so the user never hears it. Only used for
/// YouTube Music (audio-only playback); other platforms rely on phantom-PiP.
///
/// The [start]/[stop] pair is race-safe: a `stop()` that lands while a `start()`
/// is still awaiting its `play()` invalidates that start via a generation
/// counter, so the loop can never be left running after `stop()`. Unexpected
/// player stops (session deactivation, resource failure) clear the running flag
/// so the next [start] can re-establish the loop instead of being stuck.
class BackgroundAudioKeepAlive {
  BackgroundAudioKeepAlive._() {
    _player.onPlayerStateChanged.listen(_onPlayerStateChanged);
  }

  static final BackgroundAudioKeepAlive instance = BackgroundAudioKeepAlive._();

  final AudioPlayer _player = AudioPlayer();
  bool _running = false;
  int _startGeneration = 0;

  /// Bumped by [stop] so an in-flight [start] can detect it was cancelled.
  void _invalidate() {
    _startGeneration++;
  }

  /// Resets the running flag if the loop died on its own (not via [stop]),
  /// so the next [start] can bring it back. [stop] clears [_running] before
  /// stopping the player, so its own `stopped` event is ignored here.
  void _onPlayerStateChanged(PlayerState state) {
    if (!_running) return;
    if (state == PlayerState.stopped ||
        state == PlayerState.completed ||
        state == PlayerState.disposed) {
      _running = false;
      debugPrint('[MrPlay] background keep-alive stopped unexpectedly: $state');
    }
  }

  Future<void> start() async {
    if (_running) return;
    final generation = _startGeneration;
    _running = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0);
      await _player.play(AssetSource('audio/silence.wav'));
      if (generation != _startGeneration) {
        await _player.stop();
      }
    } catch (e) {
      debugPrint('[MrPlay] background keep-alive start failed: $e');
      _running = false;
    }
  }

  Future<void> stop() async {
    _invalidate();
    if (!_running) return;
    _running = false;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[MrPlay] background keep-alive stop failed: $e');
    }
  }
}