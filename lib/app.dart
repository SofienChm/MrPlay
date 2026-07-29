import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/models/platform_model.dart';
import 'data/repositories/favorites_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'presentation/router/app_router.dart';
import 'presentation/widgets/persistent_webview.dart';

class MrPlayApp extends StatefulWidget {
  final FavoritesRepository favoritesRepository;
  final SettingsRepository settingsRepository;

  const MrPlayApp({
    super.key,
    required this.favoritesRepository,
    required this.settingsRepository,
  });

  @override
  State<MrPlayApp> createState() => _MrPlayAppState();
}

class _MrPlayAppState extends State<MrPlayApp> {
  final GlobalKey<PersistentWebViewState> _webViewKey = GlobalKey();
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.settingsRepository.getThemeMode();
  }

  void _onPlatformTap(PlatformModel platform) {
    _webViewKey.currentState?.navigateTo(
      platform.url,
      platformName: platform.name,
    );
  }

  void _onPlatformUrlTap(String url) {
    _webViewKey.currentState?.navigateTo(url);
  }

  void _onThemeModeChanged(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
    widget.settingsRepository.setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: Scaffold(
        body: Stack(
          children: [
            // Main navigation (Hub, Settings, etc.)
            Navigator(
              onGenerateRoute: (settings) {
                return AppRouter.onGenerateRoute(
                  settings,
                  onPlatformTap: _onPlatformTap,
                  onPlatformUrlTap: _onPlatformUrlTap,
                  favoritesRepository: widget.favoritesRepository,
                  settingsRepository: widget.settingsRepository,
                  currentThemeMode: _themeMode,
                  onThemeModeChanged: _onThemeModeChanged,
                );
              },
            ),
            // Persistent WebView layer (hidden when not in use)
            Positioned.fill(
              child: PersistentWebView(
                key: _webViewKey,
                favoritesRepository: widget.favoritesRepository,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
