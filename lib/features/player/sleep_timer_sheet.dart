import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/palettes.dart';
import 'playback_engine.dart';
import 'sleep_timer.dart';

String formatRemaining(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m > 0 ? '$m min $s sec' : '$s sec';
}

Future<void> showSleepTimerSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: PlayerColors.sheet,
      builder: (_) => const _SleepTimerSheet(),
    );

class _SleepTimerSheet extends ConsumerWidget {
  const _SleepTimerSheet();

  bool _isActive(Duration option, Duration? remaining) =>
      remaining != null && option.inMinutes == (remaining.inSeconds / 60).ceil();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = ref.watch(sleepTimerProvider);
    final timer = ref.read(sleepTimerProvider.notifier);
    final engine = ref.read(playbackEngineProvider);
    const amber = TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.w600);

    Widget option(String label, {required bool active, required VoidCallback onTap}) => ListTile(
          title: Text(label, style: TextStyle(color: active ? Colors.amber : Colors.white)),
          trailing: active ? const Icon(Icons.check, color: Colors.amber) : null,
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sleep timer', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            if (remaining != null) Text('${formatRemaining(remaining)} left', style: amber),
            option('Off', active: remaining == null, onTap: timer.cancel),
            for (final d in SleepTimer.options)
              option(
                '${d.inMinutes} min',
                active: _isActive(d, remaining),
                onTap: () => timer.start(d, engine.pause),
              ),
          ],
        ),
      ),
    );
  }
}
