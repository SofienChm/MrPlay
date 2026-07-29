import 'package:flutter/material.dart';
import '../../data/models/platform_model.dart';
import '../../data/repositories/favorites_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../pages/hub_page.dart';
import '../pages/settings_page.dart';
import '../pages/favorites_page.dart';

typedef PlatformTapCallback = void Function(PlatformModel platform);
typedef PlatformUrlTapCallback = void Function(String url);

class AppRouter {
  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    PlatformTapCallback? onPlatformTap,
    PlatformUrlTapCallback? onPlatformUrlTap,
    FavoritesRepository? favoritesRepository,
    SettingsRepository? settingsRepository,
    ThemeMode? currentThemeMode,
    ValueChanged<ThemeMode>? onThemeModeChanged,
  }) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(
          builder: (_) => HubPage(
            onPlatformTap: onPlatformTap,
          ),
          settings: settings,
        );
      case '/settings':
        return MaterialPageRoute(
          builder: (_) => SettingsPage(
            currentThemeMode: currentThemeMode ?? ThemeMode.dark,
            onThemeModeChanged: (mode) => onThemeModeChanged?.call(mode),
            onClearHistory: () {
              // History clearing handled by native storage
              // Future: implement Hive history box clearing
            },
            onClearFavorites: () {
              favoritesRepository?.clearAll();
            },
          ),
          settings: settings,
        );
      case '/favorites':
        if (favoritesRepository == null) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Favorites not available')),
            ),
            settings: settings,
          );
        }
        return MaterialPageRoute(
          builder: (_) => FavoritesPage(
            favoritesRepository: favoritesRepository,
            onFavoriteTap: (url) => onPlatformUrlTap?.call(url),
          ),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) => HubPage(
            onPlatformTap: onPlatformTap,
          ),
          settings: settings,
        );
    }
  }
}
