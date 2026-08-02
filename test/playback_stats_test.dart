import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay/services/playback_stats_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlaybackStatsService.instance.reset();
  });

  test('recordTick banks whole seconds from sub-second deltas', () async {
    final service = PlaybackStatsService.instance;

    await service.recordTick('YouTube', Duration.zero);
    await service.recordTick('YouTube', const Duration(milliseconds: 250));
    await service.recordTick('YouTube', const Duration(milliseconds: 500));
    await service.recordTick('YouTube', const Duration(milliseconds: 750));
    await service.recordTick('YouTube', const Duration(seconds: 1));
    await service.recordTick('YouTube', const Duration(milliseconds: 1250));

    expect(await service.totalSeconds(), 1);

    final platform = await service.platformStats();
    expect(platform['YouTube'], 1);

    final daily = await service.dailyStats();
    expect(daily.values.fold<int>(0, (a, b) => a + b), 1);
  });

  test('recordTick ignores seek gaps over one minute', () async {
    final service = PlaybackStatsService.instance;

    await service.recordTick('YouTube', const Duration(seconds: 10));
    await service.recordTick('YouTube', const Duration(minutes: 5));

    expect(await service.totalSeconds(), 0);
  });
}
