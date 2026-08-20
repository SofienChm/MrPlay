import 'package:flutter/material.dart';
import '../app.dart';
import '../services/sleep_timer_service.dart';

const List<Duration?> _sleepTimerOptions = <Duration?>[
  null,
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(minutes: 60),
];

String _sleepTimerLabel(Duration? d) =>
    d == null ? 'Off' : '${d.inMinutes} min';

String _formatRemaining(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  if (minutes > 0) return '$minutes min $seconds sec';
  return '$seconds sec';
}

bool _isActiveOption(Duration? option, Duration? remaining) {
  if (option == null) return remaining == null;
  if (remaining == null) return false;
  return option.inMinutes == (remaining.inSeconds / 60).ceil();
}

/// Shows the sleep timer picker as a bottom sheet. Shared by the full player's
/// bedtime button and the 3-dot options menu.
Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    builder: (sheetContext) {
      return ValueListenableBuilder<Duration?>(
        valueListenable: SleepTimerService.instance.remaining,
        builder: (context, remaining, _) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Sleep timer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (remaining != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_formatRemaining(remaining)} left',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                for (final option in _sleepTimerOptions)
                  ListTile(
                    title: Text(
                      _sleepTimerLabel(option),
                      style: TextStyle(
                        color: _isActiveOption(option, remaining)
                            ? Colors.amber
                            : Colors.white,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      if (option == null) {
                        SleepTimerService.instance.cancel();
                      } else {
                        SleepTimerService.instance.start(option, () {
                          MrPlayApp.webViewKey.currentState
                              ?.userInitiatedPause();
                        });
                      }
                    },
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}
