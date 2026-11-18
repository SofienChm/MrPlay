import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges to the native Android Picture-in-Picture overlay via the
/// `com.mrplay/media` MethodChannel (see MainActivity.kt).
///
/// Android WebView does not implement the HTML5 `requestPictureInPicture()`
/// API (that is the iOS/Safari path), so PiP is done at the activity level:
/// the whole webview layer enters the system PiP overlay. The native side also
/// reports `pipModeChanged` events so the Flutter UI can hide its chrome while
/// the floating video window is showing.
///
/// The native `pipModeChanged` events are received by MediaControlsService,
/// which owns the single Dart-side MethodCallHandler for this channel and
/// mirrors them into [isInPip].
class PictureInPictureService {
  PictureInPictureService._();

  static final PictureInPictureService instance = PictureInPictureService._();

  static const MethodChannel _channel = MethodChannel('com.mrplay/media');

  /// True while the system PiP overlay is active (Android only).
  final ValueNotifier<bool> isInPip = ValueNotifier<bool>(false);

  bool get supported => Platform.isAndroid;

  Future<void> enter() async {
    if (!Platform.isAndroid || isInPip.value) return;
    try {
      await _channel.invokeMethod('enterPictureInPicture');
    } catch (_) {
      // No-op on devices without PiP support.
    }
  }

  Future<void> exit() async {
    if (!Platform.isAndroid || !isInPip.value) return;
    try {
      await _channel.invokeMethod('exitPictureInPicture');
    } catch (_) {}
  }

  Future<bool> query() async {
    if (!Platform.isAndroid) return false;
    try {
      final value = await _channel.invokeMethod<bool>('isInPictureInPicture');
      return value ?? false;
    } catch (_) {
      return false;
    }
  }
}
