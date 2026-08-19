import 'package:firebase_analytics/firebase_analytics.dart';

/// Thin wrapper around Firebase Analytics. All calls are fire-and-forget and
/// swallow errors, so they are safe even before Firebase is configured.
class AnalyticsService {
  AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

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
