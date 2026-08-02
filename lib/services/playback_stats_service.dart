import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aggregates watch time (per platform + per day) and tracks per-video
/// resume positions. Persists to SharedPreferences with a 5s debounce.
class PlaybackStatsService {
  PlaybackStatsService._();

  static final PlaybackStatsService instance = PlaybackStatsService._();

  static const String _dailyKey = 'stats_daily';
  static const String _platformKey = 'stats_platform';
  static const String _progressKey = 'stats_progress';
  static const int _maxProgressEntries = 200;
  static const int _minResumeSeconds = 10;

  final Map<String, int> _dailySeconds = {}; // 'YYYY-MM-DD' -> seconds
  final Map<String, int> _platformSeconds = {}; // platform -> seconds
  final Map<String, int> _progress = {}; // videoId -> seconds

  Timer? _flushTimer;
  String? _currentPlatform;
  Duration? _lastPosition;
  int _pendingMs = 0;
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _dailySeconds.addAll(_decode(prefs.getString(_dailyKey)));
    _platformSeconds.addAll(_decode(prefs.getString(_platformKey)));
    _progress.addAll(_decode(prefs.getString(_progressKey)));
    _loaded = true;
  }

  Map<String, int> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Accumulates time between successive calls while a video is playing.
  Future<void> recordTick(String platform, Duration position) async {
    await _ensureLoaded();
    if (_currentPlatform != platform) {
      _currentPlatform = platform;
      _lastPosition = null;
      _pendingMs = 0;
    }
    final last = _lastPosition;
    _lastPosition = position;
    if (last == null) return;
    final delta = position - last;
    // Ignore seeks / clock resets / gaps > 1 minute.
    if (delta <= Duration.zero || delta > const Duration(minutes: 1)) return;

    // videoState ticks arrive every ~250 ms, so individual deltas are
    // sub-second. Carry the fractional milliseconds and only bank whole
    // seconds into the maps once the accumulator crosses a full second.
    _pendingMs += delta.inMilliseconds;
    final wholeSeconds = _pendingMs ~/ 1000;
    if (wholeSeconds <= 0) return;
    _pendingMs -= wholeSeconds * 1000;
    _platformSeconds[platform] = (_platformSeconds[platform] ?? 0) + wholeSeconds;
    final day = _todayKey();
    _dailySeconds[day] = (_dailySeconds[day] ?? 0) + wholeSeconds;
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(seconds: 5), flush);
  }

  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyKey, jsonEncode(_dailySeconds));
    await prefs.setString(_platformKey, jsonEncode(_platformSeconds));
    await prefs.setString(_progressKey, jsonEncode(_progress));
  }

  /// Stops the delta tracker (call on pause / ended / new video).
  void resetTrack() {
    _lastPosition = null;
    _pendingMs = 0;
  }

  @visibleForTesting
  void reset() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _dailySeconds.clear();
    _platformSeconds.clear();
    _progress.clear();
    _currentPlatform = null;
    _lastPosition = null;
    _pendingMs = 0;
    _loaded = false;
  }

  Future<void> saveProgress(String id, Duration position) async {
    if (id.isEmpty || position <= const Duration(seconds: 3)) return;
    await _ensureLoaded();
    _progress[id] = position.inSeconds;
    if (_progress.length > _maxProgressEntries) {
      final overflow = _progress.keys.take(_progress.length - _maxProgressEntries);
      for (final key in overflow) {
        _progress.remove(key);
      }
    }
  }

  Future<void> clearProgress(String id) async {
    if (id.isEmpty) return;
    await _ensureLoaded();
    _progress.remove(id);
  }

  Future<int> resumePosition(String id) async {
    if (id.isEmpty) return 0;
    await _ensureLoaded();
    final seconds = _progress[id] ?? 0;
    return seconds >= _minResumeSeconds ? seconds : 0;
  }

  Future<Map<String, int>> dailyStats() async {
    await _ensureLoaded();
    return Map.of(_dailySeconds);
  }

  Future<Map<String, int>> platformStats() async {
    await _ensureLoaded();
    return Map.of(_platformSeconds);
  }

  Future<int> totalSeconds() async {
    await _ensureLoaded();
    return _platformSeconds.values.fold<int>(0, (sum, s) => sum + s);
  }
}
