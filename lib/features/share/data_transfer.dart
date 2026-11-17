import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/utils/log.dart';
import '../../core/utils/url_utils.dart';
import '../../data/models/models.dart';

final dataTransferProvider = Provider((ref) => DataTransfer(ref));

/// JSON export of the user's library and import from JSON / CSV files.
class DataTransfer {
  DataTransfer(this._ref);

  final Ref _ref;

  Map<String, Object?> collect() {
    final stats = _ref.read(statsRepositoryProvider);
    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'favorites': [for (final v in _ref.read(favoritesRepositoryProvider).all()) v.toJson()],
      'watchLater': [for (final v in _ref.read(watchLaterRepositoryProvider).all()) v.toJson()],
      'queue': [for (final i in _ref.read(queueRepositoryProvider).all()) i.toJson()],
      'bookmarks': [for (final s in _ref.read(shortcutRepositoryProvider).all()) s.toJson()],
      'stats': {
        'totalSeconds': stats.totalSeconds,
        'daily': stats.daily,
        'byPlatform': stats.platforms,
      },
    };
  }

  Future<void> exportJson(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
    try {
      final json = const JsonEncoder.withIndent('  ').convert(collect());
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mrplay_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(json);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'MrPlay Data Export',
        sharePositionOrigin: origin,
      );
    } on Exception catch (e) {
      log('export failed: $e');
    }
  }

  /// Imports a `.json` export or a `.csv` (title,url) file. Returns the
  /// number of items imported.
  Future<int> importFile(String path) async {
    try {
      final content = await File(path).readAsString();
      final lower = path.toLowerCase();
      if (lower.endsWith('.json')) return _importJson(content);
      if (lower.endsWith('.csv')) return _importCsv(content);
    } on Exception catch (e) {
      log('import failed: $e');
    }
    return 0;
  }

  Future<int> _importJson(String content) async {
    final data = jsonDecode(content);
    if (data is! Map) return 0;
    var count = 0;
    for (final (key, repo) in [
      ('favorites', _ref.read(favoritesRepositoryProvider)),
      ('watchLater', _ref.read(watchLaterRepositoryProvider)),
    ]) {
      final list = data[key];
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        final video = SavedVideo.fromJson(Map<String, Object?>.from(item));
        if (video == null) continue;
        await repo.add(video);
        count++;
      }
    }
    return count;
  }

  Future<int> _importCsv(String content) async {
    final repo = _ref.read(watchLaterRepositoryProvider);
    final lines = const LineSplitter().convert(content);
    var count = 0;
    for (final line in lines.skip(1)) {
      final parts = parseCsvLine(line.trim());
      if (parts.length < 2 || parts[1].isEmpty) continue;
      final url = parts[1];
      final id = UrlUtils.videoId(url);
      if (id == null || id.isEmpty) continue;
      final isYouTube = UrlUtils.isYouTube(url);
      await repo.add(
        SavedVideo(
          id: id,
          title: parts[0],
          channel: isYouTube ? 'YouTube' : (url.contains('twitch.tv') ? 'Twitch' : 'Rumble'),
          thumbnailUrl: isYouTube ? UrlUtils.youTubeThumbnail(id) : '',
          url: url,
          addedAt: DateTime.now(),
        ),
      );
      count++;
    }
    return count;
  }

  /// Splits one CSV line, honouring double-quoted fields.
  static List<String> parseCsvLine(String line) {
    if (line.isEmpty) return const [];
    final result = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (c == ',' && !inQuotes) {
        result.add(current.toString().trim());
        current.clear();
      } else {
        current.write(c);
      }
    }
    result.add(current.toString().trim());
    return result;
  }
}
