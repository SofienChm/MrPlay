import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();

  static FirebaseAnalytics get _fa => FirebaseAnalytics.instance;

  static FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _fa);

  static void logEvent(String name, [Map<String, Object>? params]) {
    try {
      _fa.logEvent(name: name, parameters: params).catchError((Object e) {
        debugPrint('Analytics event $name failed: $e');
      });
    } catch (e) {
      debugPrint('Analytics event $name failed: $e');
    }
  }

  static void logScreen(String name) {
    try {
      _fa.logScreenView(screenName: name).catchError((Object e) {
        debugPrint('Analytics screen $name failed: $e');
      });
    } catch (e) {
      debugPrint('Analytics screen $name failed: $e');
    }
  }
}
