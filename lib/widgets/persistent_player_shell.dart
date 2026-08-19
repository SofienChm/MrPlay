import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../providers/player_provider.dart';
import '../services/native_youtube_player.dart';
import 'mini_player.dart';
import 'full_player.dart';

class PersistentPlayerShell extends ConsumerWidget {
  const PersistentPlayerShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final hasVideo = state.currentVideo != null;

    if (!hasVideo) return const SizedBox.shrink();

    return Stack(
      fit: StackFit.expand,
      children: [
        // Hoisted AVPlayerLayer host. It stays mounted across the full/mini
        // swap so the layer the PiP bridge retains is never torn down (a
        // destroyed platform view silently invalidates AVPictureInPicture-
        // Controller). The 1x1 transparent frame keeps the layer in a window
        // with a non-zero size, which is all AVKit needs for PiP to be
        // possible; the visible video is the muted page behind it.
        Positioned(
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          child: IgnorePointer(
            child: ValueListenableBuilder<VideoPlayerController?>(
              valueListenable: NativeYoutubePlayer.instance.videoController,
              builder: (context, controller, _) {
                if (controller == null) return const SizedBox.shrink();
                return VideoPlayer(controller);
              },
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          top: state.isMinimized ? null : 0,
          child: state.isMinimized
              ? const MiniPlayerWidget(key: ValueKey('mini'))
              : const FullPlayerWidget(key: ValueKey('full')),
        ),
      ],
    );
  }
}