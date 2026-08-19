import 'dart:io';

import 'package:flutter/services.dart';

/// Spotlight/CoreSpotlight indexing — iOS only. On Android this is a no-op:
/// Android has no Spotlight equivalent, so indexing silently degrades.
class SpotlightService {
  SpotlightService._();

  static const MethodChannel _channel = MethodChannel('com.mrplay/spotlight');

  static bool get _isSupported => Platform.isIOS;

  static void Function(String url)? _openHandler;

  static void setOpenHandler(void Function(String url) handler) {
    _openHandler = handler;
    if (!_isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') {
        final url = call.arguments as String?;
        if (url != null && url.isNotEmpty) _openHandler?.call(url);
      }
    });
  }

  static Future<void> index({
    required String title,
    required String subtitle,
    required String url,
  }) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod('index', {
        'title': title,
        'subtitle': subtitle,
        'url': url,
      });
    } catch (_) {}
  }

  static Future<void> remove(String url) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod('remove', {'url': url});
    } catch (_) {}
  }

  static Future<void> clear() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod('clear');
    } catch (_) {}
  }
}
