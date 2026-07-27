import 'package:flutter/material.dart';
import '../pages/hub_page.dart';
import '../pages/settings_page.dart';
import '../pages/favorites_page.dart';
import '../pages/search_page.dart';

class AppRouter {
  static const String hub = '/';
  static const String settings = '/settings';
  static const String favorites = '/favorites';
  static const String search = '/search';

  static Route<dynamic> onGenerateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case hub:
        return MaterialPageRoute(builder: (_) => const HubPage());
      case settings:
        return MaterialPageRoute(builder: (_) => const SettingsPage());
      case favorites:
        return MaterialPageRoute(builder: (_) => const FavoritesPage());
      case search:
        return MaterialPageRoute(builder: (_) => const SearchPage());
      default:
        return MaterialPageRoute(builder: (_) => const HubPage());
    }
  }
}
