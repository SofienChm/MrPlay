import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Firebase has two roles in MrPlay, and they can live in different projects:
///
///  * Analytics (and everything else) uses the DEFAULT app, configured by
///    `android/app/google-services.json`. Point that file at the same Firebase
///    project as the iOS app so both platforms report to one Analytics property.
///  * Remote Config (update check + ad unit ids) stays on the original Android
///    project (`mrplay-b86c3`) through a second, explicitly configured app, so
///    swapping google-services.json never moves the remote values.
class FirebaseApps {
  FirebaseApps._();

  static const String _configAppName = 'mrplay-android-config';

  // Values of the Android Firebase project `mrplay-b86c3` (these are public
  // client identifiers, the same ones shipped in google-services.json).
  static const FirebaseOptions _configOptions = FirebaseOptions(
    apiKey: 'AIzaSyBFWLYqcriDOPpof-2dqGQw1vOfy8ZExnI',
    appId: '1:790897139670:android:13a7d99b0e483024acce77',
    messagingSenderId: '790897139670',
    projectId: 'mrplay-b86c3',
    storageBucket: 'mrplay-b86c3.firebasestorage.app',
  );

  static FirebaseApp? _configApp;

  /// Initialises the default app and the Remote Config app. Never throws.
  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[MrPlay] Firebase default init failed: $e');
    }
    try {
      _configApp = await Firebase.initializeApp(
        name: _configAppName,
        options: _configOptions,
      );
    } catch (e) {
      debugPrint('[MrPlay] Firebase config app init failed: $e');
      try {
        _configApp = Firebase.app(_configAppName);
      } catch (_) {}
    }
  }

  /// Remote Config bound to the Android project; falls back to the default app
  /// when the second app could not be created.
  static FirebaseRemoteConfig get remoteConfig {
    final app = _configApp;
    return app != null
        ? FirebaseRemoteConfig.instanceFor(app: app)
        : FirebaseRemoteConfig.instance;
  }
}
