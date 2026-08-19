import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video.dart';

class RecentActivityService {
  RecentActivityService._();

  static final RecentActivityService instance = RecentActivityService._();

  static const String _prefsKey = 'recent_videos';
  static const String _appGroupId = 'group.com.mrplay.shared';
  static const String _widgetKind = 'MrPlayRecentWidget';
  static const String _androidWidgetProvider = 'HomeWidgetProvider';
  static const String _widgetDataKey = 'recent';
  static const int _maxEntries = 5;

  bool _groupConfigured = false;

  Future<void> _configureWidget() async {
    if (_groupConfigured) return;
    if (Platform.isIOS) {
      await HomeWidget.setAppGroupId(_appGroupId);
    }
    _groupConfigured = true;
  }

  Future<List<Map<String, String>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((dynamic item) {
        final map = item as Map<String, dynamic>;
        return <String, String>{
          'title': (map['title'] as String?) ?? '',
          'url': (map['url'] as String?) ?? '',
          'platform': (map['platform'] as String?) ?? '',
        };
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> recordVideo(Video video) async {
    final entry = <String, String>{
      'title': video.title,
      'url': video.videoUrl,
      'platform': video.platform.isEmpty ? 'Web' : video.platform,
    };
    final entries = await load();
    entries.removeWhere((e) => e['url'] == video.videoUrl);
    entries.insert(0, entry);
    if (entries.length > _maxEntries) {
      entries.removeRange(_maxEntries, entries.length);
    }
    await _persist(entries);
  }

  Future<void> clear() async {
    await _persist(const []);
  }

  Future<void> _persist(List<Map<String, String>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(entries));
    try {
      await _configureWidget();
      await HomeWidget.saveWidgetData(_widgetDataKey, jsonEncode(entries));
      if (Platform.isIOS) {
        await HomeWidget.updateWidget(iOSName: _widgetKind);
      } else {
        await HomeWidget.updateWidget(androidName: _androidWidgetProvider);
      }
    } catch (_) {}
  }
}
