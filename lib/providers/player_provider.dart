import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/favorite_video.dart';
import '../data/repositories/watch_history_repository.dart';
import '../models/video.dart';
import '../services/recent_activity_service.dart';
import '../services/spotlight_service.dart';
import '../services/playback_stats_service.dart';
import '../services/analytics_service.dart';

class PlayerState {
  final Video? currentVideo;
  final bool isPlaying;
  final bool isMinimized;
  final Duration position;
  final Duration duration;

  const PlayerState({
    this.currentVideo,
    this.isPlaying = false,
    this.isMinimized = true,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  PlayerState copyWith({
    Video? currentVideo,
    bool? isPlaying,
    bool? isMinimized,
    Duration? position,
    Duration? duration,
    bool clearVideo = false,
  }) {
    return PlayerState(
      currentVideo: clearVideo ? null : (currentVideo ?? this.currentVideo),
      isPlaying: isPlaying ?? this.isPlaying,
      isMinimized: isMinimized ?? this.isMinimized,
      position: position ?? this.position,
      duration: duration ?? this.duration,
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
    WatchHistoryRepository.add(
      FavoriteVideo(
        id: video.id.isEmpty ? video.videoUrl : video.id,
        title: video.title,
        channel: video.platform.isEmpty ? 'Web' : video.platform,
        thumbnailUrl: video.thumbnailUrl,
        platformUrl: video.videoUrl,
        addedAt: DateTime.now(),
      ),
    );
    SpotlightService.index(
      title: video.title,
      subtitle: video.platform.isEmpty ? 'MrPlay' : video.platform,
      url: video.videoUrl,
    );
    AnalyticsService.logVideoPlayed(video.platform);
  }

  void syncState({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
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
      position: nextPosition,
      duration: duration ?? state.duration,
    );
  }

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
