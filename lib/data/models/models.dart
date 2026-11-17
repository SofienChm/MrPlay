import 'package:flutter/foundation.dart';

import '../../core/utils/url_utils.dart';

/// The video currently tracked by the player.
@immutable
class Video {
  const Video({
    required this.id,
    required this.title,
    required this.url,
    this.thumbnailUrl = '',
    this.platform = 'YouTube',
  });

  /// Placeholder title used until the page reports the real one.
  static const String placeholderTitle = 'Playing video';

  final String id;
  final String title;
  final String url;
  final String thumbnailUrl;
  final String platform;

  bool get hasPlaceholderTitle => title == placeholderTitle;

  /// Builds a placeholder video from a page URL (null without a usable host).
  static Video? fromUrl(String url) {
    final ytId = UrlUtils.youTubeId(url);
    if (ytId != null) {
      return Video(
        id: ytId,
        title: placeholderTitle,
        url: url,
        thumbnailUrl: UrlUtils.youTubeThumbnail(ytId),
        platform: UrlUtils.isMusic(url) ? 'Music' : 'YouTube',
      );
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return Video(
      id: url,
      title: placeholderTitle,
      url: url,
      platform: UrlUtils.platformName(uri.host),
    );
  }

  /// URL that opens the video outside MrPlay.
  String get shareUrl {
    if (url.isNotEmpty) return url;
    return id.isEmpty ? '' : 'https://www.youtube.com/watch?v=$id';
  }

  @override
  bool operator ==(Object other) =>
      other is Video &&
      other.id == id &&
      other.title == title &&
      other.url == url &&
      other.thumbnailUrl == thumbnailUrl &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(id, title, url, thumbnailUrl, platform);
}

/// A saved video (Favorites and Watch Later). Hive typeId 0.
@immutable
class SavedVideo {
  const SavedVideo({
    required this.id,
    required this.title,
    required this.channel,
    required this.thumbnailUrl,
    required this.url,
    required this.addedAt,
  });

  factory SavedVideo.fromVideo(Video v) => SavedVideo(
        id: v.id.isEmpty ? v.url : v.id,
        title: v.title,
        channel: v.platform,
        thumbnailUrl: v.thumbnailUrl,
        url: v.url,
        addedAt: DateTime.now(),
      );

  final String id;
  final String title;
  final String channel;
  final String thumbnailUrl;
  final String url;
  final DateTime addedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'channel': channel,
        'thumbnailUrl': thumbnailUrl,
        'platformUrl': url,
        'addedAt': addedAt.toIso8601String(),
      };

  static SavedVideo? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return SavedVideo(
      id: id,
      title: json['title'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      url: json['platformUrl'] as String? ?? '',
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// A user hub shortcut. Hive typeId 1.
@immutable
class Shortcut {
  const Shortcut({required this.id, required this.name, required this.url, required this.addedAt});

  final String id;
  final String name;
  final String url;
  final DateTime addedAt;

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'url': url, 'addedAt': addedAt.toIso8601String()};
}

/// An entry of the playback queue (typeId 2) or of a playlist (typeId 4).
@immutable
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.url,
    required this.platform,
    this.thumbnailUrl = '',
    this.sortIndex = 0,
    this.playlistId = '',
  });

  factory MediaItem.fromVideo(Video v, {String playlistId = ''}) {
    final key = v.id.isEmpty ? v.url : v.id;
    return MediaItem(
      id: playlistId.isEmpty ? key : '$playlistId::$key',
      title: v.title.isEmpty ? 'Untitled' : v.title,
      url: v.url,
      platform: v.platform,
      thumbnailUrl: v.thumbnailUrl,
      playlistId: playlistId,
    );
  }

  final String id;
  final String title;
  final String url;
  final String platform;
  final String thumbnailUrl;
  final int sortIndex;
  final String playlistId;

  MediaItem copyWith({int? sortIndex, String? id, String? playlistId}) => MediaItem(
        id: id ?? this.id,
        title: title,
        url: url,
        platform: platform,
        thumbnailUrl: thumbnailUrl,
        sortIndex: sortIndex ?? this.sortIndex,
        playlistId: playlistId ?? this.playlistId,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'platformUrl': url,
        'platformName': platform,
        'sortIndex': sortIndex,
      };
}

/// A user playlist. Hive typeId 3.
@immutable
class Playlist {
  const Playlist({required this.id, required this.name, required this.addedAt});

  final String id;
  final String name;
  final DateTime addedAt;
}

/// A watch-history entry (stored as JSON in preferences).
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.title,
    required this.url,
    required this.platform,
    required this.watchedAt,
  });

  final String title;
  final String url;
  final String platform;
  final DateTime watchedAt;

  Map<String, Object?> toJson() => {
        'title': title,
        'url': url,
        'platform': platform,
        'date': watchedAt.millisecondsSinceEpoch,
      };

  static HistoryEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    final date = json['date'];
    return HistoryEntry(
      title: json['title'] as String? ?? url,
      url: url,
      platform: json['platform'] as String? ?? 'Web',
      watchedAt: DateTime.fromMillisecondsSinceEpoch(date is int ? date : 0),
    );
  }
}
