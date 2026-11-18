import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/settings_repository.dart';
import 'presentation/pages/hub_page.dart';
import 'presentation/widgets/persistent_webview.dart';
import 'providers/player_provider.dart';
import 'services/analytics_service.dart';
import 'services/share_link_handler.dart';
import 'services/spotlight_service.dart';
import 'services/data_export_service.dart';
import 'services/update_check_service.dart';
import 'widgets/persistent_player_shell.dart';
import 'widgets/unified_banner_ad_slot.dart';
import 'widgets/link_resolver_sheet.dart';

class MrPlayApp extends StatefulWidget {
  const MrPlayApp({super.key});

  static final GlobalKey<PersistentWebViewState> webViewKey = GlobalKey();
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier(ThemeMode.system);
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Accent color applied app-wide (Settings > Accent Color).
  static final ValueNotifier<Color> accentColorNotifier =
      ValueNotifier(const Color(SettingsRepository.defaultAccentColor));

  /// Selected hub background palette index (Settings > Hub Background);
  /// also drives the Library / History page backgrounds like on iOS.
  static final ValueNotifier<int> hubBackgroundNotifier =
      ValueNotifier(SettingsRepository.defaultHubBackground);

  /// Enter native fullscreen automatically when the device is rotated while a
  /// video is playing (Settings > Privacy & Security > Toggles).
  static final ValueNotifier<bool> fullscreenOnRotationNotifier =
      ValueNotifier(true);

  /// Android app shortcuts (long-press on the launcher icon) deep-link through
  /// `mrplay://open?url=...`. This channel receives those URLs from
  /// MainActivity (the Android equivalent of the iOS Siri Shortcuts bridge).
  static const MethodChannel appLinkChannel = MethodChannel('com.mrplay/app');

  /// Routes a player control to the webview. The video tab (when open) is
  /// handled internally by PersistentWebView's [_activeController], so
  /// everything converges on the single webview widget.
  static void sendControl(String action, {double? position}) {
    webViewKey.currentState?.controlVideo(action, position: position);
  }

  static void enterPiP() {
    webViewKey.currentState?.enterPiP();
  }

  static void exitPiP() {
    webViewKey.currentState?.exitPiP();
  }

  static void stopAlignmentWatchdog() {
    webViewKey.currentState?.stopVideoAlignmentWatchdog();
  }

  static void startAlignmentWatchdog() {
    webViewKey.currentState?.startVideoAlignmentWatchdog();
  }

  static void closePlayer() {
    webViewKey.currentState?.closePlayer();
  }

  /// Consumes the Android system back button through the webview layer.
  /// Returns true when the press was handled (in-app navigation).
  static Future<bool> handleBack() async {
    final state = webViewKey.currentState;
    if (state == null) return false;
    return state.handleBack();
  }

  @override
  State<MrPlayApp> createState() => _MrPlayAppState();
}

class _MrPlayAppState extends State<MrPlayApp> {
  StreamSubscription<Uri?>? _widgetClickedSub;

  @override
  void initState() {
    super.initState();
    _initNativeIntegrations();
    _loadAccentAndBackground();
    _checkForUpdate();
  }

  Future<void> _loadAccentAndBackground() async {
    final accent = await SettingsRepository.getAccentColor();
    final background = await SettingsRepository.getHubBackground();
    final fullscreenOnRotation =
        await SettingsRepository.getFullscreenOnRotation();
    MrPlayApp.accentColorNotifier.value = Color(accent);
    MrPlayApp.hubBackgroundNotifier.value = background;
    MrPlayApp.fullscreenOnRotationNotifier.value = fullscreenOnRotation;
  }

  @override
  void dispose() {
    _widgetClickedSub?.cancel();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final update = await UpdateCheckService.instance.check();
      if (update == null || !mounted) return;
      _showUpdateDialog(update);
    });
  }

  void _showUpdateDialog(AppUpdate update) {
    final navigatorContext = MrPlayApp.navigatorKey.currentContext;
    if (navigatorContext == null) return;
    showDialog<void>(
      context: navigatorContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update available'),
        content: const Text(
            'A new version of MrPlay is available. Download it now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openUrl(update.downloadUrl);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Handles the Android back button: routes it through the webview layer's
  /// back stack, and exits the app when there is nothing left to go back to.
  Future<void> _handleSystemBack() async {
    final handled = await MrPlayApp.handleBack();
    if (!handled && mounted) {
      SystemNavigator.pop();
    }
  }

  void _initNativeIntegrations() {
    SpotlightService.setOpenHandler(_openExternalUrl);
    ShareLinkHandler.instance.init(
      onLink: _handleSharedLink,
      onImport: _handleImport,
    );
    _widgetClickedSub = HomeWidget.widgetClicked.listen(_openFromWidget);
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_openFromWidget);
    _initAppShortcutLinks();
  }

  /// Bridges Android app shortcuts (long-press launcher icon) into the webview.
  /// MainActivity pushes `openUrl` when a shortcut is tapped while the app runs
  /// and answers `consumePendingUrl` for launches that happen before this
  /// handler is registered. This is the Android counterpart of the iOS Siri
  /// Shortcuts integration.
  Future<void> _initAppShortcutLinks() async {
    MrPlayApp.appLinkChannel.setMethodCallHandler((call) async {
      if (call.method == 'openUrl' && call.arguments is String) {
        _openWhenReady(call.arguments as String);
      }
    });
    try {
      final pending =
          await MrPlayApp.appLinkChannel.invokeMethod<String>('consumePendingUrl');
      if (pending != null && pending.isNotEmpty) {
        _openWhenReady(pending);
      }
    } catch (_) {
      // Native side not available (not Android) — ignore.
    }
  }

  /// Waits for the persistent webview to be created before loading [url].
  Future<void> _openWhenReady(String url) async {
    for (var i = 0; i < 20; i++) {
      final state = MrPlayApp.webViewKey.currentState;
      if (state != null) {
        state.loadUrl(url);
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
              navigatorKey: MrPlayApp.navigatorKey,
              navigatorObservers: AnalyticsService.observers,
              theme: AppTheme.lightTheme(accent),
              darkTheme: AppTheme.darkTheme(accent),
              themeMode: themeMode,
              home: PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, result) {
                  if (didPop) return;
                  _handleSystemBack();
                },
                child: Scaffold(
                  body: Stack(
                    children: [
                      const HubPage(),
                      // The webview layer self-hides (SizedBox.shrink) until it
                      // is loaded. The video tab lives INSIDE PersistentWebView
                      // (see _videoTabUrl), so the app stack no longer mounts it.
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
                        child: ValueListenableBuilder<bool>(
                          valueListenable: PersistentWebViewState.layerVisible,
                          builder: (context, webviewVisible, _) {
                            // The hub shows its own inline banner; the floating
                            // one only floats over an open platform (webview
                            // layer).
                            if (!webviewVisible) return const SizedBox.shrink();
                            return Consumer(
                              builder: (context, ref, _) {
                                final state = ref.watch(playerProvider);
                                // Don't float the banner over the fullscreen
                                // player.
                                final hide = state.currentVideo != null &&
                                    !state.isMinimized;
                                return UnifiedBannerAdSlot(
                                  isVisible: !hide,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
