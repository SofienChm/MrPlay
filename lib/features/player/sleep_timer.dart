import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Remaining time of the sleep timer, or null when off. When it reaches zero
/// the registered pause callback runs.
final sleepTimerProvider = NotifierProvider<SleepTimer, Duration?>(SleepTimer.new);

class SleepTimer extends Notifier<Duration?> {
  static const List<Duration> options = [
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
  ];

  Timer? _ticker;
  DateTime? _endsAt;
  void Function()? _onFire;

  @override
  Duration? build() {
    ref.onDispose(() => _ticker?.cancel());
    return null;
  }

  bool get isActive => state != null;

  /// Starts (or restarts) the timer. Uses a wall-clock deadline so the
  /// remaining time stays right even if ticks are delayed in the background.
  void start(Duration duration, void Function() onFire) {
    cancel();
    _onFire = onFire;
    _endsAt = DateTime.now().add(duration);
    state = duration;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final endsAt = _endsAt;
    if (endsAt == null) return;
    final left = endsAt.difference(DateTime.now());
    if (left > Duration.zero) {
      state = left;
      return;
    }
    final callback = _onFire;
    cancel();
    callback?.call();
  }

  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    _onFire = null;
    state = null;
  }
}
