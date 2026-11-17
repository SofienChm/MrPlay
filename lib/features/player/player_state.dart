import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';

/// What the player UI renders. Pure state: side effects live in
/// [PlaybackEngine].
@immutable
class PlayerState {
  const PlayerState({
    this.video,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isVideoTab = false,
    this.isMinimized = true,
  });

  final Video? video;
  final bool isPlaying;
  final Duration position;
  final Duration duration;

  /// The video lives in the dedicated YouTube tab (the tab is the full player).
  final bool isVideoTab;

  /// Mini bar shown (true) or full player / expanded tab (false).
  final bool isMinimized;

  bool get hasVideo => video != null;

  double get progress {
    if (duration <= Duration.zero) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  PlayerState copyWith({
    Video? video,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? isVideoTab,
    bool? isMinimized,
  }) =>
      PlayerState(
        video: video ?? this.video,
        isPlaying: isPlaying ?? this.isPlaying,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        isVideoTab: isVideoTab ?? this.isVideoTab,
        isMinimized: isMinimized ?? this.isMinimized,
      );
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerState>(PlayerNotifier.new);

class PlayerNotifier extends Notifier<PlayerState> {
  /// Position reports right after a manual seek are ignored so the slider
  /// doesn't snap back while the element catches up.
  static const Duration seekGrace = Duration(milliseconds: 1200);
  DateTime _lastSeekAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  PlayerState build() => const PlayerState();

  /// Starts tracking [video]. A video-tab video opens expanded.
  void track(Video video, {required bool videoTab}) => state = PlayerState(
        video: video,
        isVideoTab: videoTab,
        isMinimized: !videoTab,
      );

  /// Replaces metadata only (keeps playing state and layout).
  void updateMetadata(Video video) => state = state.copyWith(video: video);

  void markVideoTab() => state = state.copyWith(isVideoTab: true, isMinimized: false);

  void sync({required bool isPlaying, Duration? position, Duration? duration}) {
    final seeking = DateTime.now().difference(_lastSeekAt) < seekGrace;
    state = state.copyWith(
      isPlaying: isPlaying,
      position: seeking ? state.position : position,
      duration: duration,
    );
  }

  void setPlaying(bool playing) => state = state.copyWith(isPlaying: playing);

  void seekTo(Duration position) {
    _lastSeekAt = DateTime.now();
    state = state.copyWith(position: position);
  }

  void minimize() => state = state.copyWith(isMinimized: true);

  void expand() => state = state.copyWith(isMinimized: false);

  void dismiss() => state = const PlayerState();
}
