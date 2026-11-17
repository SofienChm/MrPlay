import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mrplay/data/local/hive_adapters.dart';
import 'package:mrplay/data/models/models.dart';
import 'package:mrplay/data/repositories/history_repository.dart';
import 'package:mrplay/data/repositories/library_repositories.dart';
import 'package:mrplay/data/repositories/settings_repository.dart';
import 'package:mrplay/data/repositories/stats_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _video = Video(id: 'v1', title: 'Song', url: 'https://m.youtube.com/watch?v=v1', platform: 'YouTube');

MediaItem _item(String id) => MediaItem(id: id, title: id, url: 'https://x/$id', platform: 'Web');

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('mrplay_test');
    Hive.init(dir.path);
    HiveBoxes.registerAdapters();
    await HiveBoxes.openAll();
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box<SavedVideo>(HiveBoxes.favorites).clear();
    await Hive.box<MediaItem>(HiveBoxes.queue).clear();
    await Hive.box<Playlist>(HiveBoxes.playlists).clear();
    await Hive.box<PlaylistEntry>(HiveBoxes.playlistItems).clear();
  });

  test('saved videos toggle and survive a reopen (v1-compatible adapter)', () async {
    final repo = SavedVideoRepository(Hive.box<SavedVideo>(HiveBoxes.favorites));
    expect(await repo.toggle(_video), isTrue);
    expect(repo.contains('v1'), isTrue);

    await Hive.box<SavedVideo>(HiveBoxes.favorites).close();
    final reopened = SavedVideoRepository(await Hive.openBox<SavedVideo>(HiveBoxes.favorites));
    expect(reopened.all().single.title, 'Song');
    expect(await reopened.toggle(_video), isFalse);
    expect(reopened.all(), isEmpty);
  });

  test('queue keeps order, supports play-next and takes from the front', () async {
    final queue = QueueRepository(Hive.box<MediaItem>(HiveBoxes.queue));
    await queue.add(_item('a'));
    await queue.add(_item('b'));
    await queue.addNext(_item('c'));
    expect(queue.all().map((i) => i.id), ['c', 'a', 'b']);
    expect((await queue.takeNext())!.id, 'c');
    expect(queue.all().map((i) => i.id), ['a', 'b']);
    await queue.replaceAll([_item('b'), _item('a')]);
    expect(queue.all().map((i) => i.id), ['b', 'a']);
  });

  test('playlists dedupe entries and delete their items', () async {
    final repo = PlaylistRepository(
      Hive.box<Playlist>(HiveBoxes.playlists),
      Hive.box<PlaylistEntry>(HiveBoxes.playlistItems),
    );
    final gym = await repo.create('Gym');
    expect(await repo.addVideo(gym.id, _video), isTrue);
    expect(await repo.addVideo(gym.id, _video), isFalse);
    expect(repo.items(gym.id).single.title, 'Song');
    await repo.delete(gym.id);
    expect(repo.all(), isEmpty);
    expect(repo.items(gym.id), isEmpty);
  });

  group('preferences-backed', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('history is newest-first, deduped and expires', () async {
      final pushed = <int>[];
      final repo = HistoryRepository(prefs, onChanged: (e) => pushed.add(e.length));
      final now = DateTime(2026, 11, 17);
      await repo.record(_video, now: now.subtract(const Duration(days: 20)));
      await repo.record(const Video(id: 'v2', title: 'B', url: 'u2'), now: now);
      await repo.record(_video, now: now);
      expect(repo.all().map((e) => e.url), [_video.url, 'u2']);
      await repo.updateTitle('u2', 'Better');
      expect(repo.all().last.title, 'Better');
      expect(pushed, isNotEmpty);
    });

    test('stats bank whole seconds and ignore seeks', () {
      final stats = StatsRepository(prefs);
      final day = DateTime(2026, 11, 17);
      for (var ms = 0; ms <= 3000; ms += 250) {
        stats.recordTick('YouTube', Duration(milliseconds: ms), now: day);
      }
      stats.recordTick('YouTube', const Duration(minutes: 10), now: day);
      expect(stats.platforms['YouTube'], 3);
      expect(stats.daily[StatsRepository.dayKey(day)], 3);
      stats.saveProgress('v1', const Duration(seconds: 42));
      expect(stats.resumePosition('v1'), 42);
    });

    test('settings round-trip and appearance reset keeps toggles', () async {
      final repo = SettingsRepository(prefs);
      await repo.save(repo.load().copyWith(hubBackground: 3, backgroundAudio: false));
      expect(repo.load().hubBackground, 3);
      await repo.resetAppearance();
      expect(repo.load().hubBackground, 0);
      expect(repo.load().backgroundAudio, isFalse);
    });
  });
}
