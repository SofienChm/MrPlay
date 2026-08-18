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

  void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'pipStateChanged') return;
      final args = call.arguments;
      if (args is String) onStateChanged?.call(args);
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
