import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mrplay/models/video.dart';
import 'package:mrplay/services/recent_activity_service.dart';
import 'package:mrplay/data/repositories/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('recordVideo persists an entry that load() returns', () async {
    await RecentActivityService.instance.recordVideo(const Video(
      id: 'abc',
      title: 'Test video',
      videoUrl: 'https://youtube.com/watch?v=abc',
      platform: 'YouTube',
    ));

    final entries = await RecentActivityService.instance.load();
    expect(entries, hasLength(1));
    expect(entries.first['title'], 'Test video');
    expect(entries.first['url'], 'https://youtube.com/watch?v=abc');
    expect(entries.first['platform'], 'YouTube');
  });

  test('recording is skipped when watch history is disabled', () async {
    await SettingsRepository.setHistoryEnabled(false);
    await RecentActivityService.instance.recordVideo(const Video(
      id: 'abc',
      title: 'Test video',
      videoUrl: 'https://youtube.com/watch?v=abc',
    ));

    final entries = await RecentActivityService.instance.load();
    expect(entries, isEmpty);
  });

  test('re-recording the same url moves it to the top instead of duplicating',
      () async {
    final service = RecentActivityService.instance;
    await service.recordVideo(const Video(
      id: 'a',
      title: 'A',
      videoUrl: 'https://x.com/watch?v=a',
    ));
    await service.recordVideo(const Video(
      id: 'b',
      title: 'B',
      videoUrl: 'https://x.com/watch?v=b',
    ));
    await service.recordVideo(const Video(
      id: 'a',
      title: 'A again',
      videoUrl: 'https://x.com/watch?v=a',
    ));

    final entries = await service.load();
    expect(entries, hasLength(2));
    expect(entries.first['title'], 'A again');
  });

  test('clear() empties the history', () async {
    final service = RecentActivityService.instance;
    await service.recordVideo(const Video(
      id: 'a',
      title: 'A',
      videoUrl: 'https://x.com/watch?v=a',
    ));
    await service.clear();
    expect(await service.load(), isEmpty);
  });

  test('load() survives corrupted stored data', () async {
    SharedPreferences.setMockInitialValues({'recent_videos': '{not json'});
    expect(await RecentActivityService.instance.load(), isEmpty);
  });
}
