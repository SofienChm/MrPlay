import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../providers/player_provider.dart';
import 'mini_player.dart';
import 'full_player.dart';

class PersistentPlayerShell extends ConsumerStatefulWidget {
  const PersistentPlayerShell({super.key});

  @override
  ConsumerState<PersistentPlayerShell> createState() =>
      _PersistentPlayerShellState();
}

class _PersistentPlayerShellState extends ConsumerState<PersistentPlayerShell> {
  Orientation? _lastOrientation;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    final hasVideo = state.currentVideo != null;
    final orientation = MediaQuery.orientationOf(context);

    if (_lastOrientation != null && _lastOrientation != orientation) {
      final previous = _lastOrientation!;
      _lastOrientation = orientation;
      _onOrientationChanged(previous, orientation);
    } else {
      _lastOrientation = orientation;
    }

    // Rotated the phone to landscape while the video tab was collapsed ->
    // bring the tab back to fullscreen so the video fills the rotated screen.
    // Only fires on the portrait->landscape edge, so there's no feedback loop
    // (landscape->portrait leaves the tab untouched; the user can collapse
    // again with the down gesture). Deferred to a post-frame callback so the
    // notifier isn't mutated during the build itself.
    if (MrPlayApp.fullscreenOnRotationNotifier.value &&
        hasVideo &&
        state.isVideoTab &&
        state.isMinimized &&
        orientation == Orientation.landscape) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(playerProvider.notifier).expand();
      });
    }

    if (!hasVideo) return const SizedBox.shrink();

    // Video-tab playback: the tab's webview IS the full player. Only the
    // collapsed mini bar is rendered by Flutter (when the user minimizes the
    // tab); expanding just reveals the webview again. It floats just above
    // YouTube's own bottom navigation bar instead of covering it, so the feed
    // stays fully usable while the tab is collapsed.
    //
    // The webview fills to the physical screen bottom (SafeArea bottom:false),
    // and m.youtube.com already accounts for the home indicator itself, so the
    // top edge of its nav bar sits at navHeight + bottom safe inset. Mirror
    // that here so the mini bar never overlaps the nav on any device.
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const double bottomNavHeight = 52;
    final double totalBottomOffset = bottomNavHeight + bottomPadding;

    if (state.isVideoTab) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: totalBottomOffset,
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

  void _onOrientationChanged(Orientation previous, Orientation next) {
    if (!MrPlayApp.fullscreenOnRotationNotifier.value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(playerProvider);
      if (state.currentVideo == null) return;
      if (next == Orientation.landscape) {
        if (!state.isMinimized) {
          MrPlayApp.webViewKey.currentState?.controlVideo('enterFullscreen');
        }
      } else {
        MrPlayApp.webViewKey.currentState?.controlVideo('exitFullscreen');
      }
    });
  }
}
