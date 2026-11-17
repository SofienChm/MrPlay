import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';

import '../core/utils/log.dart';

/// Thin, failure-proof wrapper around Firebase Analytics.
class Analytics {
  Analytics({FirebaseAnalytics? analytics}) : _fa = analytics;

  final FirebaseAnalytics? _fa;

  FirebaseAnalytics? get _instance {
    try {
      return _fa ?? FirebaseAnalytics.instance;
    } on Object {
      return null;
    }
  }

  NavigatorObserver? get observer {
    final fa = _instance;
    return fa == null ? null : FirebaseAnalyticsObserver(analytics: fa);
  }

  void event(String name, [Map<String, Object>? params]) {
    final fa = _instance;
    if (fa == null) return;
    fa.logEvent(name: name, parameters: params).catchError((Object e) {
      log('analytics $name failed: $e');
    });
  }
}
