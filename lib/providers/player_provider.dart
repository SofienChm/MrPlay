import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video.dart';
import '../services/recent_activity_service.dart';
import '../services/spotlight_service.dart';
import '../services/playback_stats_service.dart';

class PlayerState {
  final Video? currentVideo;
  final bool isPlaying;
  final bool isMinimized;
  final bool isVideoTab;
  final Duration position;
  final Duration duration;

  const PlayerState({
    this.currentVideo,
    this.isPlaying = false,
    this.isMinimized = true,
    this.isVideoTab = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  PlayerState copyWith({
    Video? currentVideo,
    bool? isPlaying,
    bool? isMinimized,
    bool? isVideoTab,
    Duration? position,
    Duration? duration,
    bool clearVideo = false,
  }) {
    return PlayerState(
      currentVideo: clearVideo ? null : (currentVideo ?? this.currentVideo),
      isPlaying: isPlaying ?? this.isPlaying,
      isMinimized: isMinimized ?? this.isMinimized,
      isVideoTab: isVideoTab ?? this.isVideoTab,
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
      isPlaying: false,
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

  /// Tracks a video that lives in the dedicated video tab (the full YouTube
  /// page). The tab webview itself is the "full player", so no overlay is
  /// shown until the user explicitly minimizes the tab.
  void openVideoTab(Video video) {
    state = state.copyWith(
      currentVideo: video,
      isPlaying: false,
      isMinimized: false,
      isVideoTab: true,
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

  /// Marks the player as backed by a video tab without replacing metadata
  /// (used when the tab is created before the title extraction reports in).
  void videoTabActive() => state = state.copyWith(
        isVideoTab: true,
        isMinimized: false,
      );

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
