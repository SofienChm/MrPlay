import 'dart:convert';
import 'dart:math';

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video.dart';

class RecentActivityService {
  RecentActivityService._();

  static final RecentActivityService instance = RecentActivityService._();

  static const String _prefsKey = 'recent_videos';
  static const String _appGroupId = 'group.com.mrplay.shared';
  static const String _widgetKind = 'MrPlayRecentWidget';
  static const String _widgetDataKey = 'recent';
  static const int _maxEntries = 50;

  bool _groupConfigured = false;

  Future<void> _configureWidget() async {
    if (_groupConfigured) return;
    await HomeWidget.setAppGroupId(_appGroupId);
    _groupConfigured = true;
  }

  Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((dynamic item) {
        final map = item as Map<String, dynamic>;
        return <String, dynamic>{
          'title': map['title'] as String?,
          'url': map['url'] as String?,
          'platform': map['platform'] as String?,
          'date': map['date'] as int? ?? 0,
        };
      }).toList()
        ..sort((a, b) => b['date'].compareTo(a['date']));
    } catch (_) {
      return const [];
    }
  }

  Future<void> recordVideo(Video video) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{
      'title': video.title,
      'url': video.videoUrl,
      'platform': video.platform.isEmpty ? 'Web' : video.platform,
      'date': now,
    };
    final entries = await load();
    entries.removeWhere((e) => e['url'] == video.videoUrl);
    entries.insert(0, entry);
    // Keep only entries from last 15 days (15 * 24 * 60 * 60 * 1000 = 1,296,000,000 ms)
    final fifteenDaysMs = 15 * 24 * 60 * 60 * 1000;
    entries.removeWhere((e) => now - e['date'] > fifteenDaysMs);
    if (entries.length > _maxEntries) {
      entries.removeRange(_maxEntries, entries.length);
    }
    await _persist(entries);
  }

  Future<void> clear() async {
    await _persist(const []);
  }

  Future<void> _persist(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(entries));
    try {
      await _configureWidget();
      await HomeWidget.saveWidgetData(_widgetDataKey, jsonEncode(entries));
      await HomeWidget.updateWidget(iOSName: _widgetKind);
    } catch (_) {}
  }
}
