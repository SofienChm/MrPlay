import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_session/audio_session.dart';
import 'app.dart';
import 'data/models/favorite_video.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionMode: AVAudioSessionMode.moviePlayback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
  ));

  await Hive.initFlutter();
  Hive.registerAdapter(FavoriteVideoAdapter());
  runApp(const ProviderScope(child: MrPlayApp()));
}
