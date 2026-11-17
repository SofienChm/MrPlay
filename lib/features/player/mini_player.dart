import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/palettes.dart';
import 'playback_engine.dart';
import 'player_state.dart';
import 'player_widgets.dart';

/// 64pt bar: tap to expand, drag down to enter PiP, seek strip on top.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  static const double height = 64;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    final video = state.video;
    if (video == null) return const SizedBox.shrink();
    final engine = ref.read(playbackEngineProvider);
    final fade = (_drag / 200).clamp(0.0, 1.0);

    return Transform.translate(
      offset: Offset(0, _drag * 0.6),
      child: Opacity(
        opacity: 1 - fade * 0.7,
        child: GestureDetector(
          onTap: engine.expand,
          onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(0, 400)),
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 400 || _drag > 150) engine.enterPip();
            setState(() => _drag = 0);
          },
          child: Container(
            height: MiniPlayer.height,
            color: PlayerColors.sheet,
            child: Column(
              children: [
                SeekStrip(
                  progress: state.progress,
                  onSeekFraction: (f) => engine.seekTo(state.duration * f),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        VideoArtwork(video: video, size: const Size(56, 44)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                video.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 2),
                              Text(video.platform, maxLines: 1, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: state.isPlaying ? 'Pause' : 'Play',
                          icon: Icon(state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                          onPressed: engine.togglePlay,
                        ),
                        IconButton(
                          tooltip: 'Close player',
                          icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                          onPressed: engine.closePlayer,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
