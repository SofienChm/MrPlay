import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/favorite_video.dart';
import '../data/repositories/watch_history_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../models/video.dart';
import '../services/recent_activity_service.dart';
import '../services/spotlight_service.dart';
import '../services/playback_stats_service.dart';
import '../services/analytics_service.dart';

class PlayerState {
  final Video? currentVideo;
  final bool isPlaying;
  final bool isMinimized;
  final bool isVideoTab;
  final bool isInPip;

  /// When [hidePlayerUi] is true the app still tracks playback (media
  /// notification, background audio, stats) but does NOT render the Flutter
  /// mini/full player. Used for YouTube Music so its native player UI is the
  /// only one shown, while keeping lock-screen controls + background audio.
  final bool hidePlayerUi;
  final Duration position;
  final Duration duration;

  const PlayerState({
    this.currentVideo,
    this.isPlaying = false,
    this.isMinimized = true,
    this.isVideoTab = false,
    this.isInPip = false,
    this.hidePlayerUi = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  PlayerState copyWith({
    Video? currentVideo,
    bool? isPlaying,
    bool? isMinimized,
    bool? isVideoTab,
    bool? isInPip,
    bool? hidePlayerUi,
    Duration? position,
    Duration? duration,
    bool clearVideo = false,
  }) {
    return PlayerState(
      currentVideo: clearVideo ? null : (currentVideo ?? this.currentVideo),
      isPlaying: isPlaying ?? this.isPlaying,
      isMinimized: isMinimized ?? this.isMinimized,
      isVideoTab: isVideoTab ?? this.isVideoTab,
      isInPip: isInPip ?? this.isInPip,
      hidePlayerUi: hidePlayerUi ?? this.hidePlayerUi,
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
    final previous = state.currentVideo;
    state = state.copyWith(
      currentVideo: video,
      isPlaying: true,
      isMinimized: true,
      isVideoTab: false,
      position: Duration.zero,
      duration: Duration.zero,
    );
    _recordPlayback(previous, video);
  }

  /// Tracks a video that lives in the dedicated video tab (full YouTube page).
  /// isMinimized: false because the tab itself is the full player. Used by the
  /// video tab's state handler – MUST NOT be replaced with [play] (play forces
  /// isMinimized:true, which would collapse the tab before it can show).
  void openVideoTab(Video video) {
    final previous = state.currentVideo;
    state = state.copyWith(
      currentVideo: video,
      isPlaying: true,
      isMinimized: false,
      isVideoTab: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    _recordPlayback(previous, video);
  }

  /// Records history / Spotlight / analytics for a newly started video.
  /// Skipped when [video] is the same as the already-playing one (matched by id
  /// or URL), so a placeholder the JS fallback creates followed by the real
  /// metadata upgrade does not double-record the same item. History recording
  /// (RecentActivityService + WatchHistoryRepository) is gated by the "Watch
  /// history" toggle; Spotlight indexing and analytics always run so stats stay
  /// accurate even with history off.
  Future<void> _recordPlayback(Video? previous, Video video) async {
    final sameVideo = previous != null &&
        ((video.id.isNotEmpty && video.id == previous.id) ||
            (video.videoUrl.isNotEmpty && video.videoUrl == previous.videoUrl));
    if (sameVideo) return;
    final historyEnabled = await SettingsRepository.getHistoryEnabled();
    if (historyEnabled) {
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
    }
    SpotlightService.index(
      title: video.title,
      subtitle: video.platform.isEmpty ? 'MrPlay' : video.platform,
      url: video.videoUrl,
    );
    AnalyticsService.logVideoPlayed(video.platform);
  }

  /// Used when the tab is created before title extraction reports in.
  void videoTabActive() => state = state.copyWith(
        isVideoTab: true,
        isMinimized: false,
        isPlaying: true,
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

  /// Tracks the system Picture-in-Picture overlay (Android activity PiP).
  void setPipMode(bool value) => state = state.copyWith(isInPip: value);

  /// Suppresses the rendered mini/full player while still tracking playback
  /// (used for YouTube Music: native UI only, notification/background kept).
  void setHidePlayerUi(bool value) =>
      state = state.copyWith(hidePlayerUi: value);

  void dismiss() => state = const PlayerState();
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
