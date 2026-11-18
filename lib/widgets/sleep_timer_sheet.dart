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

/// Compact "time left" label, e.g. "2 min left", "45s left", "1h 5m left".
String _remainingLabel(Duration d) {
  final s = d.inSeconds;
  if (s <= 0) return 'Done';
  if (s >= 3600) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '$h h left' : '$h h $m min left';
  }
  final m = d.inMinutes;
  if (m > 0) {
    final sec = d.inSeconds % 60;
    return sec == 0
        ? '$m min left'
        : '$m:${sec.toString().padLeft(2, '0')} left';
  }
  return '${s}s left';
}

bool _isActiveOption(Duration? option, Duration? started, Duration? remaining) {
  if (option == null) return started == null && remaining == null;
  return remaining != null && option == started;
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
          final started = SleepTimerService.instance.startedDuration;
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          'Sleep timer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (remaining != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _remainingLabel(remaining),
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  for (final option in _sleepTimerOptions)
                    ListTile(
                      title: Text(
                        _sleepTimerLabel(option),
                        style: TextStyle(
                          color: _isActiveOption(option, started, remaining)
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
            ),
          );
        },
      );
    },
  );
}
