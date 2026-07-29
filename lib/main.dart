import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'data/repositories/favorites_repository.dart';
import 'data/repositories/settings_repository.dart';

final FavoritesRepository favoritesRepository = FavoritesRepository();
final SettingsRepository settingsRepository = SettingsRepository();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();

  // Initialize repositories
  await favoritesRepository.init();
  await settingsRepository.init();

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(MrPlayApp(
    favoritesRepository: favoritesRepository,
    settingsRepository: settingsRepository,
  ));
}
