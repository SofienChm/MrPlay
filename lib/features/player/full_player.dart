import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/palettes.dart';
import '../../data/models/models.dart';
import '../library/queue_page.dart';
import 'playback_engine.dart';
import 'player_state.dart';
import 'player_widgets.dart';
import 'sleep_timer.dart';
import 'sleep_timer_sheet.dart';

/// Full-screen controls for media playing in the browse tab (YouTube Music,
/// Twitch, ...). YouTube videos use the video tab itself as full player.
class FullPlayer extends ConsumerStatefulWidget {
  const FullPlayer({super.key});

  @override
  ConsumerState<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends ConsumerState<FullPlayer> {
  double _drag = 0;
  double? _scrub;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    final video = state.video;
    if (video == null) return const SizedBox.shrink();
    final engine = ref.read(playbackEngineProvider);

    return GestureDetector(
      onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(0, 600)),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 400 || _drag > 150) ref.read(playerProvider.notifier).minimize();
        setState(() => _drag = 0);
      },
      child: Transform.translate(
        offset: Offset(0, _drag),
        child: Material(
          color: Colors.black,
          child: SafeArea(
            child: Column(
              children: [
                _TopBar(onMinimize: ref.read(playerProvider.notifier).minimize, onClose: engine.closePlayer),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AspectRatio(aspectRatio: 16 / 9, child: VideoArtwork(video: video, radius: 12)),
                ),
                const SizedBox(height: 24),
                _TitleRow(video: video),
                _Scrubber(
                  state: state,
                  scrub: _scrub,
                  onChanged: (v) => setState(() => _scrub = v),
                  onEnd: (v) {
                    setState(() => _scrub = null);
                    engine.seekTo(state.duration * v);
                  },
                ),
                _TransportRow(state: state),
                const SizedBox(height: 8),
                _ToolsRow(video: video),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onMinimize, required this.onClose});

  final VoidCallback onMinimize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          IconButton(
            tooltip: 'Minimize',
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
            onPressed: onMinimize,
          ),
          const Spacer(),
          IconButton(tooltip: 'Close player', icon: const Icon(Icons.close, color: Colors.white54), onPressed: onClose),
        ],
      );
}

class _TitleRow extends ConsumerWidget {
  const _TitleRow({required this.video});

  final Video video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).valueOrNull ?? const [];
    final id = SavedVideo.fromVideo(video).id;
    final isFavorite = favorites.any((f) => f.id == id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(video.platform, style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
          IconButton(
            tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? Colors.red : Colors.white),
            onPressed: () => ref.read(favoritesRepositoryProvider).toggle(video),
          ),
        ],
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.state, required this.scrub, required this.onChanged, required this.onEnd});

  final PlayerState state;
  final double? scrub;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onEnd;

  @override
  Widget build(BuildContext context) {
    final value = scrub ?? state.progress;
    const style = TextStyle(color: Colors.white54, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Slider(
            value: value,
            activeColor: PlayerColors.progress,
            inactiveColor: Colors.white24,
            onChanged: state.duration > Duration.zero ? onChanged : null,
            onChangeEnd: onEnd,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatTime(state.duration * value), style: style),
                Text(formatTime(state.duration), style: style),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransportRow extends ConsumerWidget {
  const _TransportRow({required this.state});

  final PlayerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(playbackEngineProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Back 15 seconds',
          iconSize: 36,
          icon: const Icon(Icons.replay, color: Colors.white),
          onPressed: () => engine.seekBy(const Duration(seconds: -15)),
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: state.isPlaying ? 'Pause' : 'Play',
          iconSize: 72,
          icon: Icon(state.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
          onPressed: engine.togglePlay,
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: 'Forward 15 seconds',
          iconSize: 36,
          icon: const Icon(Icons.forward_10, color: Colors.white),
          onPressed: () => engine.seekBy(const Duration(seconds: 15)),
        ),
      ],
    );
  }
}

class _ToolsRow extends ConsumerWidget {
  const _ToolsRow({required this.video});

  final Video video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(playbackEngineProvider);
    final queue = ref.read(queueRepositoryProvider);
    final sleepActive = ref.watch(sleepTimerProvider) != null;
    final watchLater = ref.watch(watchLaterProvider).valueOrNull ?? const [];
    final inWatchLater = watchLater.any((w) => w.id == SavedVideo.fromVideo(video).id);
    final messenger = ScaffoldMessenger.of(context);

    void snack(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 1)));

    final tools = <(IconData, String, VoidCallback, Color)>[
      (Icons.subtitles, 'Captions', engine.toggleCaptions, Colors.white),
      (Icons.picture_in_picture_alt, 'Picture in picture', engine.togglePip, Colors.white),
      (Icons.fullscreen, 'Fullscreen', engine.toggleFullscreen, Colors.white),
      (
        Icons.playlist_play,
        'Play next',
        () async {
          await queue.addNext(MediaItem.fromVideo(video));
          snack('Will play next');
        },
        Colors.white,
      ),
      (
        Icons.playlist_add,
        'Add to queue',
        () async {
          await queue.add(MediaItem.fromVideo(video));
          snack('Added to queue');
        },
        Colors.white,
      ),
      (
        Icons.queue_music,
        'Open queue',
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QueuePage())),
        Colors.white,
      ),
      (
        inWatchLater ? Icons.bookmark : Icons.bookmark_border,
        'Watch later',
        () => ref.read(watchLaterRepositoryProvider).toggle(video),
        Colors.white,
      ),
      (Icons.bedtime, 'Sleep timer', () => showSleepTimerSheet(context), sleepActive ? Colors.amber : Colors.white),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (final (icon, label, onTap, color) in tools)
          IconButton(tooltip: label, icon: Icon(icon, color: color), onPressed: onTap),
      ],
    );
  }
}
