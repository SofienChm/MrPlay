import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Watch-time stats (per day and per platform) and per-video resume points.
/// Writes are debounced (5s); call [flush] on pause/close.
class StatsRepository {
  StatsRepository(this._prefs) {
    _daily.addAll(_decode(_dailyKey));
    _platforms.addAll(_decode(_platformKey));
    _progress.addAll(_decode(_progressKey));
  }

  final SharedPreferences _prefs;

  static const _dailyKey = 'stats_daily';
  static const _platformKey = 'stats_platform';
  static const _progressKey = 'stats_progress';
  static const int _maxProgressEntries = 200;
  static const int _maxDays = 90;
  static const Duration _maxTickGap = Duration(minutes: 1);

  final Map<String, int> _daily = {};
  final Map<String, int> _platforms = {};
  final Map<String, int> _progress = {};

  Timer? _flushTimer;
  String? _platform;
  Duration? _lastPosition;
  int _pendingMs = 0;

  Map<String, int> _decode(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return {};
      return {
        for (final e in map.entries)
          if (e.key is String && e.value is num) e.key as String: (e.value as num).toInt(),
      };
    } on FormatException {
      return {};
    }
  }

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Accumulates the time between consecutive position reports while playing.
  /// Seeks, clock resets and gaps over a minute are ignored.
  void recordTick(String platform, Duration position, {DateTime? now}) {
    if (_platform != platform) {
      _platform = platform;
      _lastPosition = null;
      _pendingMs = 0;
    }
    final last = _lastPosition;
    _lastPosition = position;
    if (last == null) return;
    final delta = position - last;
    if (delta <= Duration.zero || delta > _maxTickGap) return;
    _pendingMs += delta.inMilliseconds;
    final seconds = _pendingMs ~/ 1000;
    if (seconds <= 0) return;
    _pendingMs -= seconds * 1000;
    _platforms[platform] = (_platforms[platform] ?? 0) + seconds;
    final day = dayKey(now ?? DateTime.now());
    _daily[day] = (_daily[day] ?? 0) + seconds;
    _flushTimer ??= Timer(const Duration(seconds: 5), flush);
  }

  /// Stops delta tracking (pause / ended / new video).
  void resetTrack() {
    _lastPosition = null;
    _pendingMs = 0;
  }

  void saveProgress(String videoId, Duration position) {
    if (videoId.isEmpty || position <= const Duration(seconds: 3)) return;
    _progress.remove(videoId);
    _progress[videoId] = position.inSeconds;
    while (_progress.length > _maxProgressEntries) {
      _progress.remove(_progress.keys.first);
    }
  }

  void clearProgress(String videoId) => _progress.remove(videoId);

  /// Resume point in seconds (0 when under 10s or unknown).
  int resumePosition(String videoId) {
    final s = _progress[videoId] ?? 0;
    return s >= 10 ? s : 0;
  }

  Map<String, int> get daily => Map.unmodifiable(_daily);
  Map<String, int> get platforms => Map.unmodifiable(_platforms);
  int get totalSeconds => _platforms.values.fold(0, (a, b) => a + b);

  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final cutoff = dayKey(DateTime.now().subtract(const Duration(days: _maxDays)));
    _daily.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    await Future.wait([
      _prefs.setString(_dailyKey, jsonEncode(_daily)),
      _prefs.setString(_platformKey, jsonEncode(_platforms)),
      _prefs.setString(_progressKey, jsonEncode(_progress)),
    ]);
  }
}
