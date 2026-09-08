import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_session/audio_session.dart';
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

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionMode: AVAudioSessionMode.moviePlayback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
  ));

  await MobileAds.instance.initialize();
  await _requestTrackingPermission();

  await Hive.initFlutter();
  Hive.registerAdapter(FavoriteVideoAdapter());
  Hive.registerAdapter(CustomBookmarkAdapter());
  Hive.registerAdapter(QueueItemAdapter());
  Hive.registerAdapter(PlaylistAdapter());
  Hive.registerAdapter(PlaylistItemAdapter());
  runApp(const ProviderScope(child: MrPlayApp()));
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
  } catch (_) {}
}
