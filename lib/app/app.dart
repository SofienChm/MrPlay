import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/platforms.dart';
import '../core/theme/app_theme.dart';
import '../features/player/playback_engine.dart';
import '../features/share/data_transfer.dart';
import '../features/share/link_sheet.dart';
import '../features/share/share_intents.dart';
import 'providers.dart';
import 'shell.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

class MrPlayApp extends ConsumerStatefulWidget {
  const MrPlayApp({super.key});

  @override
  ConsumerState<MrPlayApp> createState() => _MrPlayAppState();
}

class _MrPlayAppState extends ConsumerState<MrPlayApp> {
  final _shareIntents = ShareIntents();
  StreamSubscription<String>? _widgetLinks;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
    );
    // Eagerly create the engine so it observes the app lifecycle from start.
    ref.read(playbackEngineProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initIntegrations());
  }

  void _initIntegrations() {
    ref.read(spotlightProvider).listen(_open);
    unawaited(
      ref.read(siriProvider).init(
            onOpen: _open,
            shortcuts: [
              for (final p in Platforms.builtIn)
                (id: 'platform-${p.name.toLowerCase()}', title: 'Open ${p.name} in MrPlay', url: p.url),
            ],
          ),
    );
    _widgetLinks = ref.read(homeWidgetProvider).openedUrls.listen(_open);
    _shareIntents.listen(onLink: _onSharedLink, onFile: _onSharedFile);
  }

  void _open(String url) {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    ref.read(playbackEngineProvider).loadUrl(url);
  }

  void _onSharedLink(String url) {
    final context = navigatorKey.currentContext;
    if (context != null) unawaited(showLinkSheet(context, url));
  }

  Future<void> _onSharedFile(String path) async {
    final count = await ref.read(dataTransferProvider).importFile(path);
    messengerKey.currentState?.showSnackBar(SnackBar(content: Text('Imported $count items')));
  }

  @override
  void dispose() {
    _shareIntents.dispose();
    unawaited(_widgetLinks?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final observer = ref.watch(analyticsProvider).observer;
    return MaterialApp(
      title: 'MrPlay',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: AppTheme.light(settings.accentColor),
      darkTheme: AppTheme.dark(settings.accentColor),
      themeMode: settings.themeMode,
      navigatorObservers: [if (observer != null) observer],
      home: const AppShell(),
    );
  }
}
