import 'package:flutter/services.dart';

import '../core/constants/platform_constants.dart';

/// Registers NSUserActivity-based Siri shortcuts ("Open" a platform) and
/// forwards invocations from Siri, the Shortcuts app, or lock-screen
/// suggestions into the in-app web view.
class SiriShortcutsService {
  SiriShortcutsService._();

  static final SiriShortcutsService instance = SiriShortcutsService._();

  static const MethodChannel _channel = MethodChannel('com.mrplay/siri');

  static void Function(String url)? _openHandler;

  bool _initialized = false;

  void setOpenHandler(void Function(String url) handler) {
    _openHandler = handler;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShortcut') {
        final args = call.arguments as Map?;
        final url = args?['url'] as String?;
        if (url != null && url.isNotEmpty) {
          _openHandler?.call(url);
        }
      }
      return null;
    });

    try {
      final pending = await _channel.invokeMethod<String>('consumePending');
      if (pending != null && pending.isNotEmpty) {
        _openHandler?.call(pending);
      }
    } catch (_) {
      // Native side unavailable (e.g. non-iOS platform).
    }

    await registerPlatformShortcuts();
  }

  /// Advertises one shortcut per platform so the actions appear in the
  /// Shortcuts app, in Settings → Siri & Search, and in Siri Suggestions.
  Future<void> registerPlatformShortcuts() async {
    final shortcuts = PlatformConstants.platforms.take(8).map((platform) {
      return <String, String>{
        'id': 'platform-${platform.name.toLowerCase()}',
        'title': 'Open ${platform.name} in MrPlay',
        'url': platform.url,
      };
    }).toList();
    if (shortcuts.isEmpty) return;
    try {
      await _channel.invokeMethod('register', {'shortcuts': shortcuts});
    } catch (_) {
      // ignore
    }
  }

  /// Refreshes the "current" activity whenever the user opens a platform,
  /// letting iOS suggest the last-used one on the lock screen.
  Future<void> setCurrent({required String name, required String url}) async {
    try {
      await _channel.invokeMethod('setCurrent', {'name': name, 'url': url});
    } catch (_) {
      // ignore
    }
  }
}
