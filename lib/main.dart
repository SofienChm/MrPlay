import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_session/audio_session.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
import 'data/models/favorite_video.dart';
import 'data/models/custom_bookmark.dart';
import 'data/models/queue_item.dart';
import 'data/models/playlist.dart';
import 'data/models/playlist_item.dart';
import 'services/remote_config_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await RemoteConfigService.instance.initialize();

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionMode: AVAudioSessionMode.moviePlayback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
  ));

  await MobileAds.instance.initialize();

  await Hive.initFlutter();
  Hive.registerAdapter(FavoriteVideoAdapter());
  Hive.registerAdapter(CustomBookmarkAdapter());
  Hive.registerAdapter(QueueItemAdapter());
  Hive.registerAdapter(PlaylistAdapter());
  Hive.registerAdapter(PlaylistItemAdapter());
  runApp(const ProviderScope(child: MrPlayApp()));
}
