import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'core/theme/app_theme.dart';
import 'presentation/pages/hub_page.dart';
import 'presentation/widgets/persistent_webview.dart';
import 'providers/player_provider.dart';
import 'services/share_link_handler.dart';
import 'services/spotlight_service.dart';
import 'services/data_export_service.dart';
import 'widgets/persistent_player_shell.dart';
import 'widgets/unified_banner_ad_slot.dart';
import 'widgets/link_resolver_sheet.dart';

class MrPlayApp extends StatefulWidget {
  const MrPlayApp({super.key});

  static final GlobalKey<PersistentWebViewState> webViewKey = GlobalKey();
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);

  @override
  State<MrPlayApp> createState() => _MrPlayAppState();
}

class _MrPlayAppState extends State<MrPlayApp> {
  StreamSubscription<Uri?>? _widgetClickedSub;

  @override
  void initState() {
    super.initState();
    _initNativeIntegrations();
  }

  @override
  void dispose() {
    _widgetClickedSub?.cancel();
    super.dispose();
  }

  void _initNativeIntegrations() {
    SpotlightService.setOpenHandler(_openExternalUrl);
    ShareLinkHandler.instance.init(
      onLink: _handleSharedLink,
      onImport: _handleImport,
    );
    _widgetClickedSub = HomeWidget.widgetClicked.listen(_openFromWidget);
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_openFromWidget);
  }

  void _openExternalUrl(String url) {
    MrPlayApp.webViewKey.currentState?.loadUrl(url);
  }

  void _handleSharedLink(String url) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (sheetContext) {
        return LinkResolverSheet(key: ValueKey(url), url: url);
      },
    ).then((action) {
      if (action == 'play' || action == 'open' || action == null) {
        MrPlayApp.webViewKey.currentState?.loadUrl(url);
      }
    });
  }

  Future<void> _handleImport(String filePath, String type) async {
    final service = DataExportService.instance;
    int imported = 0;
    if (type == 'json') {
      imported = await service.importFromJsonFile(filePath);
    } else if (type == 'csv') {
      imported = await service.importFromCsvFile(filePath);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported $imported items'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openFromWidget(Uri? uri) {
    if (uri == null) return;
    final url = uri.queryParameters['url'];
    if (url != null && url.isNotEmpty) {
      MrPlayApp.webViewKey.currentState?.loadUrl(url);
    }
  }

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
                  child: SafeArea(
                    child: PersistentWebView(key: MrPlayApp.webViewKey),
                  ),
                ),
                const PersistentPlayerShell(),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 80,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final state = ref.watch(playerProvider);
                      // Don't float the banner over the fullscreen player.
                      final hide =
                          state.currentVideo != null && !state.isMinimized;
                      return UnifiedBannerAdSlot(isVisible: !hide);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
