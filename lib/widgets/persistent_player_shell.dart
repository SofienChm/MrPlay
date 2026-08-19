import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import 'mini_player.dart';
import 'full_player.dart';

class PersistentPlayerShell extends ConsumerWidget {
  const PersistentPlayerShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final hasVideo = state.currentVideo != null;

    if (!hasVideo) return const SizedBox.shrink();

    // Video-tab playback: the tab's webview IS the full player. Only the
    // collapsed mini bar is rendered by Flutter (when the user minimizes the
    // tab); expanding just reveals the webview again. It floats just above
    // YouTube's own bottom navigation bar (~50px) instead of covering it, so
    // the feed stays fully usable while the tab is collapsed.
    if (state.isVideoTab) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 52,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeIn,
          child: state.isMinimized
              ? MiniPlayerWidget(key: const ValueKey('video-tab-mini'))
              : const SizedBox.shrink(key: ValueKey('video-tab-hidden')),
        ),
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      top: state.isMinimized ? null : 0,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeIn,
        switchOutCurve: Curves.easeIn,
        child: state.isMinimized
            ? const MiniPlayerWidget(key: ValueKey('mini'))
            : const FullPlayerWidget(key: ValueKey('full')),
      ),
    );
  }
}
