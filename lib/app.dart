import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'presentation/pages/hub_page.dart';
import 'presentation/pages/favorites_page.dart';
import 'presentation/pages/settings_page.dart';
import 'presentation/widgets/persistent_webview.dart';
import 'widgets/persistent_player_shell.dart';

class MrPlayApp extends StatefulWidget {
  const MrPlayApp({super.key});

  static final GlobalKey<PersistentWebViewState> webViewKey = GlobalKey();
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);

  @override
  State<MrPlayApp> createState() => _MrPlayAppState();
}

class _MrPlayAppState extends State<MrPlayApp> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: MrPlayApp.themeModeNotifier,
      builder: (context, themeMode, _) {
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        );
        return MaterialApp(
          title: 'MrPlay',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: Scaffold(
            body: SafeArea(
              child: Stack(
                children: [
                  IndexedStack(
                    index: _currentTab,
                    children: [
                      HubPage(
                        onNavigateToFavorites: () => setState(() => _currentTab = 1),
                        onNavigateToSettings: () => setState(() => _currentTab = 2),
                      ),
                      const FavoritesPage(),
                      const SettingsPage(),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: PersistentWebView(key: MrPlayApp.webViewKey),
                  ),
                  const PersistentPlayerShell(),
                ],
              ),
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _currentTab,
              onTap: (index) => setState(() => _currentTab = index),
              type: BottomNavigationBarType.fixed,
              backgroundColor: const Color(0xFF1C1C1E),
              selectedItemColor: Colors.red,
              unselectedItemColor: Colors.grey,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.favorite_rounded),
                  label: 'Favorites',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
