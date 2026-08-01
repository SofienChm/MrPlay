import 'package:flutter/services.dart';

class SpotlightService {
  SpotlightService._();

  static const MethodChannel _channel = MethodChannel('com.mrplay/spotlight');

  static void Function(String url)? _openHandler;

  static void setOpenHandler(void Function(String url) handler) {
    _openHandler = handler;
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
    try {
      await _channel.invokeMethod('index', {
        'title': title,
        'subtitle': subtitle,
        'url': url,
      });
    } catch (_) {}
  }

  static Future<void> remove(String url) async {
    try {
      await _channel.invokeMethod('remove', {'url': url});
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await _channel.invokeMethod('clear');
    } catch (_) {}
  }
}
