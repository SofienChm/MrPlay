import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/settings_repository.dart';

/// Playback and content switches. The engine applies ad/popup changes to the
/// live webviews by listening to [settingsProvider].
class TogglesPage extends ConsumerWidget {
  const TogglesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    void set(AppSettings Function(AppSettings) change) =>
        ref.read(settingsProvider.notifier).update(change);

    return Scaffold(
      appBar: AppBar(title: const Text('Toggles')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.screen_rotation_outlined),
            title: const Text('Enter fullscreen on device rotation'),
            subtitle: const Text('Rotate your device to watch in fullscreen'),
            value: s.fullscreenOnRotation,
            onChanged: (v) => set((s) => s.copyWith(fullscreenOnRotation: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.history),
            title: const Text('Watch history'),
            subtitle: const Text('Record watched videos'),
            value: s.historyEnabled,
            onChanged: (v) => set((s) => s.copyWith(historyEnabled: v)),
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.block),
            title: const Text('Block ads & trackers'),
            subtitle: const Text('Removes ads inside websites'),
            value: s.adBlock,
            onChanged: (v) => set((s) => s.copyWith(adBlock: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.pages_outlined),
            title: const Text('Block pop-ups'),
            subtitle: const Text('Stops script pop-ups and ad redirects'),
            value: s.blockPopups,
            onChanged: (v) => set((s) => s.copyWith(blockPopups: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.audiotrack_outlined),
            title: const Text('Background audio'),
            subtitle: const Text('Keep playing when the app is in the background'),
            value: s.backgroundAudio,
            onChanged: (v) => set((s) => s.copyWith(backgroundAudio: v)),
          ),
        ],
      ),
    );
  }
}
