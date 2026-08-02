import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mrplay/data/models/custom_bookmark.dart';
import 'package:mrplay/data/models/favorite_video.dart';
import 'package:mrplay/data/models/queue_item.dart';
import 'package:mrplay/data/repositories/custom_bookmarks_repository.dart';
import 'package:mrplay/data/repositories/queue_repository.dart';
import 'package:mrplay/data/repositories/watch_later_repository.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() {
    hiveDir = Directory.systemTemp.createTempSync('mrplay_repo_test');
    Hive.init(hiveDir.path);
    Hive.registerAdapter(FavoriteVideoAdapter());
    Hive.registerAdapter(CustomBookmarkAdapter());
    Hive.registerAdapter(QueueItemAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  test('WatchLaterRepository add / isQueued / remove round-trip', () async {
    final video = FavoriteVideo(
      id: 'v1',
      title: 'Test Video',
      channel: 'YouTube',
      thumbnailUrl: 'https://i.ytimg.com/vi/v1/hqdefault.jpg',
      platformUrl: 'https://m.youtube.com/watch?v=v1',
      addedAt: DateTime(2026, 1, 1),
    );

    await WatchLaterRepository.add(video);
    expect(await WatchLaterRepository.isQueued('v1'), isTrue);

    final all = await WatchLaterRepository.getAll();
    expect(all.length, 1);
    expect(all.first.title, 'Test Video');

    await WatchLaterRepository.remove('v1');
    expect(await WatchLaterRepository.isQueued('v1'), isFalse);
  });

  test('CustomBookmark adapter round-trip keeps all fields', () async {
    final bookmark = CustomBookmark(
      id: 'b1',
      name: 'My Site',
      url: 'https://example.com',
      addedAt: DateTime(2026, 2, 2),
    );

    await CustomBookmarksRepository.add(bookmark);
    final all = await CustomBookmarksRepository.getAll();

    expect(all.length, 1);
    expect(all.first.id, 'b1');
    expect(all.first.name, 'My Site');
    expect(all.first.url, 'https://example.com');
    expect(all.first.addedAt, DateTime(2026, 2, 2));

    await CustomBookmarksRepository.remove('b1');
    expect(await CustomBookmarksRepository.getAll(), isEmpty);
  });

  test('Watch Later and Favorites boxes stay independent', () async {
    final video = FavoriteVideo(
      id: 'shared-id',
      title: 'Queued Only',
      channel: 'YouTube',
      thumbnailUrl: '',
      platformUrl: 'https://m.youtube.com/watch?v=shared-id',
      addedAt: DateTime.now(),
    );
    await WatchLaterRepository.add(video);

    final favoritesBox = await Hive.openBox<FavoriteVideo>('favorites');
    expect(favoritesBox.containsKey('shared-id'), isFalse);

    await WatchLaterRepository.remove('shared-id');
  });

  test('QueueRepository add / addNext / reorder round-trip', () async {
    QueueItem item(String id, String title, int sort) => QueueItem(
          id: id,
          title: title,
          thumbnailUrl: '',
          platformUrl: 'https://m.youtube.com/watch?v=$id',
          platformName: 'YouTube',
          sortIndex: sort,
        );

    await QueueRepository.add(item('a', 'A', 0));
    await QueueRepository.add(item('b', 'B', 0));
    expect((await QueueRepository.getAll()).length, 2);

    await QueueRepository.addNext(item('c', 'C', 0));
    final afterNext = await QueueRepository.getAll();
    expect(afterNext.first.id, 'c');

    await QueueRepository.reorder([
      afterNext[1],
      afterNext[2],
      afterNext[0],
    ]);
    final reordered = await QueueRepository.getAll();
    expect(reordered.map((e) => e.id).toList(), ['a', 'b', 'c']);

    await QueueRepository.remove('a');
    final remaining = await QueueRepository.getAll();
    expect(remaining.map((e) => e.id).toList(), ['b', 'c']);

    await QueueRepository.clear();
    expect(await QueueRepository.getAll(), isEmpty);
  });
}
