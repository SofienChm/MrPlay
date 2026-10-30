import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_session/audio_session.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'app.dart';
import 'data/models/favorite_video.dart';
import 'data/models/custom_bookmark.dart';
import 'data/models/queue_item.dart';
import 'data/models/playlist.dart';
import 'data/models/playlist_item.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  // Order matters (consent -> ATT -> ads init, all before the audio session is
  // configured below so ad audio can't override it). Each step is bounded so a
  // bad network can't hold the first screen hostage.
  await _waitUntilAppActive();
  await _gatherConsent();
  await _requestTrackingPermission();
  try {
    await MobileAds.instance
        .initialize()
        .timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('[MrPlay] MobileAds init failed or timed out: $e');
  }

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionMode: AVAudioSessionMode.moviePlayback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
  ));

  await Hive.initFlutter();
  Hive.registerAdapter(FavoriteVideoAdapter());
  Hive.registerAdapter(CustomBookmarkAdapter());
  Hive.registerAdapter(QueueItemAdapter());
  Hive.registerAdapter(PlaylistAdapter());
  Hive.registerAdapter(PlaylistItemAdapter());
  runApp(const ProviderScope(child: MrPlayApp()));
}

/// Runs the Google UMP consent flow (GDPR/EEA/UK). Shows the consent form only
/// when required; never blocks app start on failure.
Future<void> _gatherConsent() async {
  final done = Completer<void>();
  final infoReady = Completer<void>();
  ConsentInformation.instance.requestConsentInfoUpdate(
    ConsentRequestParameters(),
    () async {
      if (!infoReady.isCompleted) infoReady.complete();
      try {
        await ConsentForm.loadAndShowConsentFormIfRequired((_) {
          if (!done.isCompleted) done.complete();
        });
      } catch (_) {
        if (!done.isCompleted) done.complete();
      }
    },
    (_) {
      if (!infoReady.isCompleted) infoReady.complete();
      if (!done.isCompleted) done.complete();
    },
  );
  // Only the network request is short-bounded; once the info arrived, give the
  // user plenty of time to read the consent form before moving on.
  var infoArrived = true;
  await infoReady.future.timeout(const Duration(seconds: 6), onTimeout: () {
    infoArrived = false;
  });
  if (infoArrived) {
    await done.future.timeout(const Duration(seconds: 120), onTimeout: () {});
  }
}

/// The UMP form and the ATT prompt only appear while the app is active; asking
/// before iOS reports it as resumed can silently skip them. Waits briefly.
Future<void> _waitUntilAppActive() async {
  for (var i = 0; i < 30; i++) {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Requests App Tracking Transparency authorization for personalized AdMob ads
/// (required by iOS 14.5+ when serving ads that use the IDFA). Safely no-ops on
/// platforms without the ATT framework.
Future<void> _requestTrackingPermission() async {
  try {
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  } catch (e) { debugPrint('[MrPlay] ATT request failed: $e'); }
}
