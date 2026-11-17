import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/hive_adapters.dart';
import '../data/models/models.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/library_repositories.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/stats_repository.dart';
import '../services/analytics.dart';
import '../services/home_widget_sync.dart';
import '../services/keep_alive_audio.dart';
import '../services/native_channels.dart';

/// Overridden in `main()` with the instance loaded at startup.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

// ---------------------------------------------------------------- services

final analyticsProvider = Provider((ref) => Analytics());
final spotlightProvider = Provider((ref) => SpotlightService());
final siriProvider = Provider((ref) => SiriService());
final nowPlayingProvider = Provider((ref) => NowPlayingService());
final homeWidgetProvider = Provider((ref) => HomeWidgetSync());
final keepAliveAudioProvider = Provider((ref) => KeepAliveAudio());

// ------------------------------------------------------------ repositories

final favoritesRepositoryProvider =
    Provider((ref) => SavedVideoRepository(Hive.box<SavedVideo>(HiveBoxes.favorites)));
final watchLaterRepositoryProvider =
    Provider((ref) => SavedVideoRepository(Hive.box<SavedVideo>(HiveBoxes.watchLater)));
final shortcutRepositoryProvider =
    Provider((ref) => ShortcutRepository(Hive.box<Shortcut>(HiveBoxes.shortcuts)));
final queueRepositoryProvider =
    Provider((ref) => QueueRepository(Hive.box<MediaItem>(HiveBoxes.queue)));
final playlistRepositoryProvider = Provider(
  (ref) => PlaylistRepository(
    Hive.box<Playlist>(HiveBoxes.playlists),
    Hive.box<PlaylistEntry>(HiveBoxes.playlistItems),
  ),
);
final historyRepositoryProvider = Provider((ref) {
  final widget = ref.watch(homeWidgetProvider);
  return HistoryRepository(ref.watch(sharedPreferencesProvider), onChanged: widget.push);
});
final statsRepositoryProvider = Provider((ref) => StatsRepository(ref.watch(sharedPreferencesProvider)));
final settingsRepositoryProvider =
    Provider((ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)));

// ------------------------------------------------------------ live lists

final favoritesProvider = StreamProvider((ref) => ref.watch(favoritesRepositoryProvider).watch());
final watchLaterProvider = StreamProvider((ref) => ref.watch(watchLaterRepositoryProvider).watch());
final shortcutsProvider = StreamProvider((ref) => ref.watch(shortcutRepositoryProvider).watch());
final queueProvider = StreamProvider((ref) => ref.watch(queueRepositoryProvider).watch());
final playlistsProvider = StreamProvider((ref) => ref.watch(playlistRepositoryProvider).watch());
final playlistItemsProvider = StreamProvider.family<List<MediaItem>, String>(
  (ref, playlistId) => ref.watch(playlistRepositoryProvider).watchItems(playlistId),
);
final historyProvider = StreamProvider((ref) => ref.watch(historyRepositoryProvider).watch());

// ---------------------------------------------------------------- settings

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> update(AppSettings Function(AppSettings current) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).save(state);
  }

  /// "Clear cache": theme, accent, background and default platform go back to
  /// their defaults. Playback toggles are kept.
  Future<void> resetAppearance() async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.resetAppearance();
    state = repo.load();
  }
}
