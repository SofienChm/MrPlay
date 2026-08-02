import 'dart:async';
import 'package:flutter/foundation.dart';

/// Countdown that pauses playback when it fires. Survives player
/// minimize/expand because it lives outside the widget tree.
class SleepTimerService {
  SleepTimerService._();

  static final SleepTimerService instance = SleepTimerService._();

  Timer? _fireTimer;
  Timer? _ticker;
  VoidCallback? _onFire;

  /// Remaining time, or null when no timer is armed.
  final ValueNotifier<Duration?> remaining = ValueNotifier<Duration?>(null);

  bool get isActive => remaining.value != null;

  void start(Duration duration, VoidCallback onFire) {
    cancel();
    _onFire = onFire;
    remaining.value = duration;
    _fireTimer = Timer(duration, _fire);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = remaining.value;
      if (r == null) return;
      final next = r - const Duration(seconds: 1);
      remaining.value = next.isNegative ? Duration.zero : next;
    });
  }

  void _fire() {
    final callback = _onFire;
    cancel();
    callback?.call();
  }

  void cancel() {
    _fireTimer?.cancel();
    _fireTimer = null;
    _ticker?.cancel();
    _ticker = null;
    _onFire = null;
    remaining.value = null;
  }
}
