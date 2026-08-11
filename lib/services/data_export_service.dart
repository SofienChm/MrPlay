import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models/favorite_video.dart';
import '../data/repositories/favorites_repository.dart';
import '../data/repositories/watch_later_repository.dart';
import '../data/repositories/custom_bookmarks_repository.dart';
import '../data/repositories/queue_repository.dart';
import 'playback_stats_service.dart';

class DataExportService {
  DataExportService._();
  static final DataExportService instance = DataExportService._();

  Future<Map<String, dynamic>> _collectAllData() async {
    final favorites = await FavoritesRepository.getAll();
    final watchLater = await WatchLaterRepository.getAll();
    final queue = await QueueRepository.getAll();
    final bookmarks = await CustomBookmarksRepository.getAll();
    final dailyStats = await PlaybackStatsService.instance.dailyStats();
    final platformStats = await PlaybackStatsService.instance.platformStats();
    final totalSeconds = await PlaybackStatsService.instance.totalSeconds();

    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'favorites': favorites
          .map((f) => {
                'id': f.id,
                'title': f.title,
                'channel': f.channel,
                'thumbnailUrl': f.thumbnailUrl,
                'platformUrl': f.platformUrl,
                'addedAt': f.addedAt.toIso8601String(),
              })
          .toList(),
      'watchLater': watchLater
          .map((w) => {
                'id': w.id,
                'title': w.title,
                'channel': w.channel,
                'thumbnailUrl': w.thumbnailUrl,
                'platformUrl': w.platformUrl,
                'addedAt': w.addedAt.toIso8601String(),
              })
          .toList(),
      'queue': queue
          .map((q) => {
                'id': q.id,
                'title': q.title,
                'thumbnailUrl': q.thumbnailUrl,
                'platformUrl': q.platformUrl,
                'platformName': q.platformName,
                'sortIndex': q.sortIndex,
              })
          .toList(),
      'bookmarks': bookmarks
          .map((b) => {
                'id': b.id,
                'name': b.name,
                'url': b.url,
                'addedAt': b.addedAt.toIso8601String(),
              })
          .toList(),
      'stats': {
        'totalSeconds': totalSeconds,
        'daily': dailyStats,
        'byPlatform': platformStats,
      },
    };
  }

  Future<String?> exportToJson() async {
    try {
      final data = await _collectAllData();
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/mrplay_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonString);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'MrPlay Data Export',
      );
      return jsonString;
    } catch (_) {
      return null;
    }
  }

  Future<int> importFromJsonFile(String filePath) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      var imported = 0;

      final versions = <String, List<dynamic>>{};
      if (data.containsKey('favorites')) {
        versions['favorites'] = data['favorites'] as List<dynamic>;
      }
      if (data.containsKey('watchLater')) {
        versions['watchLater'] = data['watchLater'] as List<dynamic>;
      }

      for (final entry in versions.entries) {
        for (final item in entry.value) {
          try {
            final map = item as Map<String, dynamic>;
            final fav = FavoriteVideo(
              id: (map['id'] as String?) ?? '',
              title: (map['title'] as String?) ?? '',
              channel: (map['channel'] as String?) ?? '',
              thumbnailUrl: (map['thumbnailUrl'] as String?) ?? '',
              platformUrl: (map['platformUrl'] as String?) ?? '',
              addedAt: _parseDateTime(map['addedAt']),
            );
            if (fav.id.isEmpty) continue;
            if (entry.key == 'favorites') {
              await FavoritesRepository.add(fav);
            } else {
              await WatchLaterRepository.add(fav);
            }
            imported++;
          } catch (_) {}
        }
      }

      return imported;
    } catch (_) {
      return 0;
    }
  }

  Future<int> importFromCsvFile(String filePath) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final lines = content.split('\n');
      if (lines.length < 2) return 0;
      var imported = 0;

      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final parts = _splitCsvLine(line);
        if (parts.length < 2) continue;

        final title = parts[0];
        final url = parts[1];

        if (url.isEmpty) continue;

        final videoId = _extractVideoId(url);
        if (videoId.isEmpty) continue;

        try {
          final platform = url.contains('youtube') || url.contains('youtu.be')
              ? 'YouTube'
              : url.contains('twitch.tv')
                  ? 'Twitch'
                  : 'Rumble';

          await WatchLaterRepository.add(
            FavoriteVideo(
              id: videoId,
              title: title,
              channel: platform,
              thumbnailUrl: url.contains('youtube') || url.contains('youtu.be')
                  ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg'
                  : '',
              platformUrl: url,
              addedAt: DateTime.now(),
            ),
          );
          imported++;
        } catch (_) {}
      }

      return imported;
    } catch (_) {
      return 0;
    }
  }

  List<String> _splitCsvLine(String line) {
    final result = <String>[];
    var current = '';
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        result.add(current.trim());
        current = '';
      } else {
        current += c;
      }
    }
    result.add(current.trim());
    return result;
  }

  String _extractVideoId(String url) {
    var match = RegExp(r'[?&]v=([^&]+)').firstMatch(url);
    if (match != null) return match.group(1)!;
    match = RegExp(r'youtu\.be/([^?&]+)').firstMatch(url);
    if (match != null) return match.group(1)!;
    match = RegExp(r'twitch\.tv/videos/(\d+)').firstMatch(url);
    if (match != null) return match.group(1)!;
    return '';
  }

  DateTime _parseDateTime(dynamic value) {
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }
}
