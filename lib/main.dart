import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_session/audio_session.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'app.dart';
import 'data/models/favorite_video.dart';
import 'data/models/custom_bookmark.dart';
import 'data/models/queue_item.dart';
import 'data/models/playlist.dart';
import 'data/repositories/settings_repository.dart';
import 'services/ad_config_service.dart';
import 'services/firebase_apps.dart';

/// Runs the Google UMP consent flow. Shows the consent form only when required
/// (EEA/UK users); never blocks app start on failure.
Future<void> _gatherConsent() async {
  final done = Completer<void>();
  final infoReady = Completer<void>();
  try {
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
  } catch (_) {
    return;
  }
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = await AudioSession.instance;
  // iOS needs a dedicated AVAudioSession so the WebView keeps playing audio
  // in the background / on the lock screen. Android gets the music recipe
  // (media content type + audio focus) instead; the `av*` fields are ignored.
  await session.configure(
    Platform.isIOS
        ? const AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playback,
            avAudioSessionMode: AVAudioSessionMode.moviePlayback,
            avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
          )
        : const AudioSessionConfiguration.music(),
  );

  // Firebase is optional until google-services.json is added; if it isn't
  // configured the app simply skips update checks.
  try {
    await FirebaseApps.init();
  } catch (_) {}

  // Pull the AdMob banner unit id from Remote Config (defaults to the Google
  // test unit). Fire-and-forget: the banner swaps itself to the remote key
  // when the value lands, so startup isn't blocked on the network.
  AdConfigService.instance.init();

  // Google UMP consent (GDPR / EEA / UK) must be gathered before ads are
  // initialised. Bounded so a bad network can't hold the first screen hostage.
  await _gatherConsent();
  try {
    await MobileAds.instance.initialize().timeout(const Duration(seconds: 8));
  } catch (_) {}

  await Hive.initFlutter();
  Hive.registerAdapter(FavoriteVideoAdapter());
  Hive.registerAdapter(CustomBookmarkAdapter());
  Hive.registerAdapter(QueueItemAdapter());
  Hive.registerAdapter(PlaylistItemAdapter());
  Hive.registerAdapter(PlaylistAdapter());

  // Apply the persisted theme before the first frame. The notifier defaults to
  // ThemeMode.system, so without this the app would start light even when a
  // dark theme was saved (and only the Settings page used to restore it).
  final savedTheme = await SettingsRepository.getThemeMode();
  MrPlayApp.themeModeNotifier.value = switch (savedTheme) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  runApp(const ProviderScope(child: MrPlayApp()));
}
