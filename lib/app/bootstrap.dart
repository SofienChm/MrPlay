import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:audio_session/audio_session.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/log.dart';
import '../data/local/hive_adapters.dart';
import '../features/browser/web_scripts.dart';

/// Everything the first frame needs.
class Bootstrap {
  const Bootstrap({required this.prefs, required this.scripts});

  final SharedPreferences prefs;
  final WebScripts scripts;

  /// Order matters: consent → ATT → ads, all before the audio session is
  /// configured, so ad audio can't override it. Each network-bound step is
  /// time-boxed so a bad connection never holds the first screen hostage.
  static Future<Bootstrap> run() async {
    WidgetsFlutterBinding.ensureInitialized();

    final local = _initLocal();
    await _guard('firebase', Firebase.initializeApp);
    await _waitUntilActive();
    await _guard('consent', _gatherConsent);
    await _guard('tracking', _requestTracking);
    await _guard('ads', () => MobileAds.instance.initialize().timeout(const Duration(seconds: 8)));
    await _guard('audio session', _configureAudioSession);
    return local;
  }

  static Future<Bootstrap> _initLocal() async {
    await Hive.initFlutter();
    HiveBoxes.registerAdapters();
    final (prefs, scripts, _) = await (
      SharedPreferences.getInstance(),
      WebScripts.load(),
      HiveBoxes.openAll(),
    ).wait;
    return Bootstrap(prefs: prefs, scripts: scripts);
  }

  static Future<void> _guard(String step, Future<Object?> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      log('startup step "$step" failed: $e');
    }
  }

  static Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.moviePlayback,
      ),
    );
  }

  /// The UMP form and ATT prompt only show while the app is active.
  static Future<void> _waitUntilActive() async {
    for (var i = 0; i < 30; i++) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Google UMP consent (GDPR). Only the info request is short-bounded; once
  /// it arrived the user gets time to read the form.
  static Future<void> _gatherConsent() async {
    final infoReady = Completer<bool>();
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        if (!infoReady.isCompleted) infoReady.complete(true);
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((_) {
            if (!done.isCompleted) done.complete();
          });
        } on Object {
          if (!done.isCompleted) done.complete();
        }
      },
      (_) {
        if (!infoReady.isCompleted) infoReady.complete(false);
        if (!done.isCompleted) done.complete();
      },
    );
    final arrived = await infoReady.future.timeout(const Duration(seconds: 6), onTimeout: () => false);
    if (arrived) await done.future.timeout(const Duration(seconds: 120), onTimeout: () {});
  }

  static Future<void> _requestTracking() async {
    if (await AppTrackingTransparency.trackingAuthorizationStatus == TrackingStatus.notDetermined) {
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  }
}
