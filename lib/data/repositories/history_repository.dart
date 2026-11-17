import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Watch history kept on-device: newest first, 50 entries, 15 days.
class HistoryRepository {
  HistoryRepository(this._prefs, {this.onChanged});

  final SharedPreferences _prefs;

  /// Called after every write (e.g. to refresh the home-screen widget).
  final void Function(List<HistoryEntry> entries)? onChanged;

  static const _key = 'recent_videos';
  static const int maxEntries = 50;
  static const Duration maxAge = Duration(days: 15);

  final _changes = StreamController<List<HistoryEntry>>.broadcast();

  List<HistoryEntry> all() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.map(HistoryEntry.fromJson).whereType<HistoryEntry>().toList()
        ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    } on FormatException {
      return [];
    }
  }

  Stream<List<HistoryEntry>> watch() async* {
    yield all();
    yield* _changes.stream;
  }

  Future<void> record(Video video, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final entries = all()
      ..removeWhere((e) => e.url == video.url)
      ..insert(
        0,
        HistoryEntry(
          title: video.title,
          url: video.url,
          platform: video.platform.isEmpty ? 'Web' : video.platform,
          watchedAt: at,
        ),
      )
      ..removeWhere((e) => at.difference(e.watchedAt) > maxAge);
    if (entries.length > maxEntries) entries.removeRange(maxEntries, entries.length);
    await _persist(entries);
  }

  /// Updates the title of an entry recorded with a placeholder title.
  Future<void> updateTitle(String url, String title) async {
    final entries = all();
    final i = entries.indexWhere((e) => e.url == url);
    if (i < 0 || entries[i].title == title) return;
    final e = entries[i];
    entries[i] = HistoryEntry(title: title, url: e.url, platform: e.platform, watchedAt: e.watchedAt);
    await _persist(entries);
  }

  Future<void> clear() => _persist(const []);

  Future<void> _persist(List<HistoryEntry> entries) async {
    await _prefs.setString(_key, jsonEncode(entries.map((e) => e.toJson()).toList()));
    _changes.add(entries);
    onChanged?.call(entries);
  }
}
