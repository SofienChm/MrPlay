import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'presentation/pages/hub_page.dart';
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
            body: Stack(
              children: [
                const HubPage(),
                Positioned.fill(
                  child: PersistentWebView(key: MrPlayApp.webViewKey),
                ),
                const PersistentPlayerShell(),
              ],
            ),
          ),
        );
      },
    );
  }
}
