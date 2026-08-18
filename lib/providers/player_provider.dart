import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video.dart';
import '../services/recent_activity_service.dart';
import '../services/spotlight_service.dart';
import '../services/playback_stats_service.dart';

class PlayerState {
  final Video? currentVideo;
  final bool isPlaying;
  final bool isMinimized;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final String? loadError;

  const PlayerState({
    this.currentVideo,
    this.isPlaying = false,
    this.isMinimized = true,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.loadError,
  });

  PlayerState copyWith({
    Video? currentVideo,
    bool? isPlaying,
    bool? isMinimized,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    String? loadError,
    bool clearVideo = false,
  }) {
    return PlayerState(
      currentVideo: clearVideo ? null : (currentVideo ?? this.currentVideo),
      isPlaying: isPlaying ?? this.isPlaying,
      isMinimized: isMinimized ?? this.isMinimized,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      loadError: loadError ?? this.loadError,
    );
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  /// Timestamp of the last manual [seekTo]. While a seek is still "in flight"
  /// (the video element may take a moment to jump), JS position reports are
  /// ignored so they don't snap the slider/thumb back to the pre-seek time.
  DateTime _lastSeekAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _seekGrace = Duration(milliseconds: 1200);

  @override
  PlayerState build() => const PlayerState();

  void play(Video video) {
    state = state.copyWith(
      currentVideo: video,
      isPlaying: true,
      isMinimized: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    RecentActivityService.instance.recordVideo(video);
    SpotlightService.index(
      title: video.title,
      subtitle: video.platform.isEmpty ? 'MrPlay' : video.platform,
      url: video.videoUrl,
    );
  }

  void syncState({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? buffering,
    bool ended = false,
  }) {
    final playing = ended ? false : (isPlaying ?? state.isPlaying);
    if (playing && position != null) {
      final platform = state.currentVideo?.platform ?? 'YouTube';
      PlaybackStatsService.instance.recordTick(platform, position);
    } else if (ended) {
      PlaybackStatsService.instance.resetTrack();
    }
    // Ignore JS position reports that arrive right after a manual seek, so the
    // slider thumb doesn't jump back to the pre-seek position while the video
    // element catches up.
    final recentlySeeked =
        DateTime.now().difference(_lastSeekAt) < _seekGrace;
    final nextPosition = (recentlySeeked && position != null)
        ? state.position
        : (position ?? state.position);
    state = state.copyWith(
      isPlaying: playing,
      isBuffering: buffering ?? state.isBuffering,
      position: nextPosition,
      duration: duration ?? state.duration,
    );
  }

  /// Surfaces a playback/load failure in the player UI.
  void declareError(String message) =>
      state = state.copyWith(isPlaying: false, loadError: message);

  void clearError() => state = state.copyWith(loadError: null);

  void updateMetadata(Video video) =>
      state = state.copyWith(currentVideo: video);

  void pause() => state = state.copyWith(isPlaying: false);

  void resume() => state = state.copyWith(isPlaying: true);

  void seekTo(Duration position) {
    _lastSeekAt = DateTime.now();
    state = state.copyWith(position: position);
  }

  void minimize() => state = state.copyWith(isMinimized: true);

  void expand() => state = state.copyWith(isMinimized: false);

  void dismiss() => state = const PlayerState();
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
