import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'full_player.dart';
import 'mini_player.dart';
import 'playback_engine.dart';
import 'player_state.dart';

/// Mini bar / full player above the browser, plus rotate-to-fullscreen.
///
/// For the YouTube video tab, the tab itself is the full player: only the
/// collapsed mini bar is drawn, floating just above YouTube's bottom nav.
class PlayerOverlay extends ConsumerStatefulWidget {
  const PlayerOverlay({super.key});

  /// Height of m.youtube.com's bottom navigation bar.
  static const double youTubeNavHeight = 52;

  @override
  ConsumerState<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends ConsumerState<PlayerOverlay> {
  Orientation? _orientation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (_orientation != null && _orientation != orientation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(playbackEngineProvider).onOrientationChanged(landscape: orientation == Orientation.landscape);
      });
    }
    _orientation = orientation;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    if (!state.hasVideo) return const SizedBox.shrink();
    const duration = Duration(milliseconds: 280);

    if (state.isVideoTab) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: PlayerOverlay.youTubeNavHeight + MediaQuery.paddingOf(context).bottom,
        child: AnimatedSwitcher(
          duration: duration,
          child: state.isMinimized ? const MiniPlayer(key: ValueKey('tab-mini')) : const SizedBox.shrink(),
        ),
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      top: state.isMinimized ? null : 0,
      child: AnimatedSwitcher(
        duration: duration,
        child: state.isMinimized
            ? const SafeArea(top: false, child: MiniPlayer(key: ValueKey('mini')))
            : const FullPlayer(key: ValueKey('full')),
      ),
    );
  }
}
