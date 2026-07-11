import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/animated_splash_screen.dart';
import 'services/audio_handler.dart';
import 'services/media_manager.dart';

final audioHandler = MrPlayAudioHandler();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  MediaManager.instance.init(audioHandler);
  final prefs = await SharedPreferences.getInstance();
  final autoLaunchYouTube = prefs.getBool('auto_launch_youtube') ?? false;
  runApp(MrPlayApp(autoLaunchYouTube: autoLaunchYouTube));
}

class MrPlayApp extends StatelessWidget {
  final bool autoLaunchYouTube;

  const MrPlayApp({super.key, required this.autoLaunchYouTube});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MrPlay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: AnimatedSplashScreen(autoLaunchYouTube: autoLaunchYouTube),
    );
  }
}
