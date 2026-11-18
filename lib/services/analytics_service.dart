import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';

/// Thin wrapper around Firebase Analytics. All calls are fire-and-forget and
/// swallow errors, so they are safe even before Firebase is configured.
class AnalyticsService {
  AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Navigator observer that reports a screen_view for every pushed page.
  static List<NavigatorObserver> get observers {
    try {
      return [FirebaseAnalyticsObserver(analytics: _analytics)];
    } catch (_) {
      return const []; // Firebase not initialised
    }
  }

  static Future<void> logScreen(String name) async {
    try {
      await _analytics.logScreenView(screenName: name);
    } catch (_) {}
  }

  static Future<void> logPlatformOpened(String name) => _log(
        'platform_opened',
        {'platform': name},
      );

  static Future<void> logVideoPlayed(String platform) => _log(
        'video_played',
        {'platform': platform.isEmpty ? 'Web' : platform},
      );

  static Future<void> logSearch(String query) => _log(
        'search',
        {'query': query},
      );

  static Future<void> logShare() => _log('share', {});

  static Future<void> logEvent(String name, [Map<String, Object>? params]) =>
      _log(name, params ?? const {});

  static Future<void> _log(String name, Map<String, Object> params) async {
    try {
      await _analytics.logEvent(name: name, parameters: params);
    } catch (_) {}
  }
}
