import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'presentation/router/app_router.dart';
import 'presentation/widgets/persistent_webview.dart';

class MrPlayApp extends StatelessWidget {
  const MrPlayApp({super.key});

  static final GlobalKey<PersistentWebViewState> webViewKey = GlobalKey();
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
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
                Navigator(
                  onGenerateRoute: AppRouter.onGenerateRoute,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: PersistentWebView(key: webViewKey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
