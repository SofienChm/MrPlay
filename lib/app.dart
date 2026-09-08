import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/settings_repository.dart';
import 'presentation/pages/hub_page.dart';
import 'presentation/widgets/persistent_webview.dart';
import 'providers/player_provider.dart';
import 'services/share_link_handler.dart';
import 'services/spotlight_service.dart';
import 'services/siri_shortcuts_service.dart';
import 'services/data_export_service.dart';
import 'widgets/persistent_player_shell.dart';
import 'widgets/unified_banner_ad_slot.dart';
import 'widgets/link_resolver_sheet.dart';

class MrPlayApp extends StatefulWidget {
  const MrPlayApp({super.key});

  static final GlobalKey<PersistentWebViewState> webViewKey = GlobalKey();
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);
  static final ValueNotifier<Color> accentColorNotifier =
      ValueNotifier(const Color(SettingsRepository.defaultAccentColor));
  static final ValueNotifier<int> hubBackgroundNotifier = ValueNotifier(0);
  static final ValueNotifier<bool> fullscreenOnRotationNotifier =
      ValueNotifier(true);

  /// A backgrounded session older than this is reset when the app resumes.
  static const Duration _sessionTimeout = Duration(hours: 1);

  @override
  State<MrPlayApp> createState() => _MrPlayAppState();
}

class _MrPlayAppState extends State<MrPlayApp> with WidgetsBindingObserver {
  StreamSubscription<Uri?>? _widgetClickedSub;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAccent();
    _initNativeIntegrations();
  }

  Future<void> _loadAccent() async {
    final value = await SettingsRepository.getAccentColor();
    MrPlayApp.accentColorNotifier.value = Color(value);
    MrPlayApp.hubBackgroundNotifier.value =
        await SettingsRepository.getHubBackground();
    MrPlayApp.fullscreenOnRotationNotifier.value =
        await SettingsRepository.getFullscreenOnRotation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetClickedSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _pausedAt ??= DateTime.now();
        break;
      case AppLifecycleState.resumed:
        final pausedAt = _pausedAt;
        if (pausedAt != null) {
          _pausedAt = null;
          if (DateTime.now().difference(pausedAt) >= MrPlayApp._sessionTimeout) {
            MrPlayApp.webViewKey.currentState?.resetToHub();
          }
        }
        break;
      default:
        break;
    }
  }

  void _initNativeIntegrations() {
    SpotlightService.setOpenHandler(_openExternalUrl);
    SiriShortcutsService.instance.setOpenHandler(_openWhenReady);
    SiriShortcutsService.instance.init();
    ShareLinkHandler.instance.init(
      onLink: _handleSharedLink,
      onImport: _handleImport,
    );
    _widgetClickedSub = HomeWidget.widgetClicked.listen(_openFromWidget);
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_openFromWidget);
  }

  Future<void> _openWhenReady(String url) async {
    for (var i = 0; i < 20; i++) {
      final controller = MrPlayApp.webViewKey.currentState;
      if (controller != null) {
        controller.loadUrl(url);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
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
        return ValueListenableBuilder<Color>(
          valueListenable: MrPlayApp.accentColorNotifier,
          builder: (context, accent, _) {
            return MaterialApp(
              title: 'MrPlay',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme(accent),
              darkTheme: AppTheme.darkTheme(accent),
              themeMode: themeMode,
              home: Scaffold(
            body: Stack(
              children: [
                const HubPage(),
                Positioned.fill(
                  child: SafeArea(
                    bottom: false,
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
                      // The hub shows its own small ad slot, so keep the
                      // floating banner hidden while the hub is visible.
                      return ValueListenableBuilder<bool>(
                        valueListenable: PersistentWebViewState.hubVisible,
                        builder: (context, hubVisible, _) {
                          return UnifiedBannerAdSlot(
                            isVisible: !hubVisible && !hide,
                            alignment: Alignment.centerLeft,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
            ),
          );
          },
        );
      },
    );
  }
}
