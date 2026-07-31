import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video.dart';

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
  }

  void syncState({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool ended = false,
  }) {
    state = state.copyWith(
      isPlaying: ended ? false : (isPlaying ?? state.isPlaying),
      position: position ?? state.position,
      duration: duration ?? state.duration,
    );
  }

  void pause() => state = state.copyWith(isPlaying: false);

  void resume() => state = state.copyWith(isPlaying: true);

  void seekTo(Duration position) => state = state.copyWith(position: position);

  void minimize() => state = state.copyWith(isMinimized: true);

  void expand() => state = state.copyWith(isMinimized: false);

  void dismiss() => state = const PlayerState();
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
