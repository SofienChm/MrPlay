import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/providers.dart';
import 'features/player/playback_engine.dart';

Future<void> main() async {
  final boot = await Bootstrap.run();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(boot.prefs),
        webScriptsProvider.overrideWithValue(boot.scripts),
      ],
      child: const MrPlayApp(),
    ),
  );
}
