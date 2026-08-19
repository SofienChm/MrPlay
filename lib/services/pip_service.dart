import 'dart:async';

import 'package:flutter/services.dart';

/// Bridges to the native `com.mrplay/pip` channel (iOS only).
///
/// Drives the native [AVPictureInPictureController] attached to the video
/// surface and reports PiP lifecycle back to Dart.
class PiPService {
  PiPService._();

  static final PiPService instance = PiPService._();

  static const MethodChannel _channel = MethodChannel('com.mrplay/pip');

  /// Notified with `started`, `stopped` or `restoreUI`.
  void Function(String state)? onStateChanged;

  /// Completes when the native layer is ready for PiP (`pipReady`). Reset on
  /// every [prepare].
  Completer<void>? _readyCompleter;

  void init() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pipStateChanged':
          final args = call.arguments;
          if (args is String) onStateChanged?.call(args);
          break;
        case 'pipReady':
          final c = _readyCompleter;
          if (c != null && !c.isCompleted) c.complete();
          break;
      }
    });
  }

  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isPiPAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isActive() async {
    try {
      return await _channel.invokeMethod<bool>('isPiPActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Links the native PiP controller to the playing surface without opening a
  /// PiP window, and enables automatic PiP when the app backgrounds. Instead of
  /// guessing at a delay, this returns when the bridge KVO-reports that
  /// `isPictureInPicturePossible` flipped on (with a hard timeout as a safety
  /// net), so a home-screen swipe hands off to PiP seamlessly.
  Future<void> prepare() async {
    _readyCompleter = Completer<void>();
    try {
      await _channel.invokeMethod('prepare');
    } catch (_) {}
    await _readyCompleter!.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    _readyCompleter = null;
  }

  /// Releases the native PiP controller / retained layer.
  Future<void> clear() async {
    _readyCompleter = null;
    try {
      await _channel.invokeMethod('clear');
    } catch (_) {}
  }

  Future<void> enterPiP() async {
    try {
      await _channel.invokeMethod('enterPiP');
    } catch (_) {}
  }

  Future<void> exitPiP() async {
    try {
      await _channel.invokeMethod('exitPiP');
    } catch (_) {}
  }
}
