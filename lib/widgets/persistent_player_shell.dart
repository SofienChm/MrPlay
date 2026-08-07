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

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      top: state.isMinimized ? null : 0,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: state.isMinimized
            ? const MiniPlayerWidget(key: ValueKey('mini'))
            : const FullPlayerWidget(key: ValueKey('full')),
      ),
    );
  }
}
