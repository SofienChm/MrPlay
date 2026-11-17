import 'package:hive/hive.dart';

import '../models/models.dart';

// Hand-written adapters. Type IDs and field indices are identical to v1, so
// data saved by the App Store build is read back unchanged after the update.

Map<int, Object?> _readFields(BinaryReader reader) {
  final count = reader.readByte();
  return {for (var i = 0; i < count; i++) reader.readByte(): reader.read()};
}

void _writeFields(BinaryWriter writer, List<Object?> values) {
  writer.writeByte(values.length);
  for (var i = 0; i < values.length; i++) {
    writer
      ..writeByte(i)
      ..write(values[i]);
  }
}

class SavedVideoAdapter extends TypeAdapter<SavedVideo> {
  @override
  final int typeId = 0;

  @override
  SavedVideo read(BinaryReader reader) {
    final f = _readFields(reader);
    return SavedVideo(
      id: f[0] as String,
      title: f[1] as String? ?? '',
      channel: f[2] as String? ?? '',
      thumbnailUrl: f[3] as String? ?? '',
      url: f[4] as String? ?? '',
      addedAt: f[5] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, SavedVideo obj) => _writeFields(
        writer,
        [obj.id, obj.title, obj.channel, obj.thumbnailUrl, obj.url, obj.addedAt],
      );
}

class ShortcutAdapter extends TypeAdapter<Shortcut> {
  @override
  final int typeId = 1;

  @override
  Shortcut read(BinaryReader reader) {
    final f = _readFields(reader);
    return Shortcut(
      id: f[0] as String,
      name: f[1] as String? ?? '',
      url: f[2] as String? ?? '',
      addedAt: f[3] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, Shortcut obj) =>
      _writeFields(writer, [obj.id, obj.name, obj.url, obj.addedAt]);
}

class QueueItemAdapter extends TypeAdapter<MediaItem> {
  @override
  final int typeId = 2;

  @override
  MediaItem read(BinaryReader reader) {
    final f = _readFields(reader);
    return MediaItem(
      id: f[0] as String,
      title: f[1] as String? ?? '',
      thumbnailUrl: f[2] as String? ?? '',
      url: f[3] as String? ?? '',
      platform: f[4] as String? ?? '',
      sortIndex: f[5] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, MediaItem obj) => _writeFields(
        writer,
        [obj.id, obj.title, obj.thumbnailUrl, obj.url, obj.platform, obj.sortIndex],
      );
}

class PlaylistAdapter extends TypeAdapter<Playlist> {
  @override
  final int typeId = 3;

  @override
  Playlist read(BinaryReader reader) {
    final f = _readFields(reader);
    return Playlist(
      id: f[0] as String,
      name: f[1] as String? ?? '',
      addedAt: f[2] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, Playlist obj) =>
      _writeFields(writer, [obj.id, obj.name, obj.addedAt]);
}

/// Playlist entries are the same [MediaItem] shape plus the playlist id.
/// Hive allows one adapter per Dart type, so playlist entries are stored
/// through this wrapper type.
class PlaylistEntry {
  const PlaylistEntry(this.item);
  final MediaItem item;
}

class PlaylistEntryAdapter extends TypeAdapter<PlaylistEntry> {
  @override
  final int typeId = 4;

  @override
  PlaylistEntry read(BinaryReader reader) {
    final f = _readFields(reader);
    return PlaylistEntry(
      MediaItem(
        id: f[0] as String,
        title: f[1] as String? ?? '',
        thumbnailUrl: f[2] as String? ?? '',
        url: f[3] as String? ?? '',
        platform: f[4] as String? ?? '',
        playlistId: f[5] as String? ?? '',
        sortIndex: f[6] as int? ?? 0,
      ),
    );
  }

  @override
  void write(BinaryWriter writer, PlaylistEntry obj) {
    final i = obj.item;
    _writeFields(
      writer,
      [i.id, i.title, i.thumbnailUrl, i.url, i.platform, i.playlistId, i.sortIndex],
    );
  }
}

abstract final class HiveBoxes {
  static const String favorites = 'favorites';
  static const String watchLater = 'watch_later';
  static const String shortcuts = 'custom_bookmarks';
  static const String queue = 'playback_queue';
  static const String playlists = 'playlists';
  static const String playlistItems = 'playlist_items';

  static void registerAdapters() {
    if (Hive.isAdapterRegistered(0)) return;
    Hive
      ..registerAdapter(SavedVideoAdapter())
      ..registerAdapter(ShortcutAdapter())
      ..registerAdapter(QueueItemAdapter())
      ..registerAdapter(PlaylistAdapter())
      ..registerAdapter(PlaylistEntryAdapter());
  }

  static Future<void> openAll() async {
    await Future.wait([
      Hive.openBox<SavedVideo>(favorites),
      Hive.openBox<SavedVideo>(watchLater),
      Hive.openBox<Shortcut>(shortcuts),
      Hive.openBox<MediaItem>(queue),
      Hive.openBox<Playlist>(playlists),
      Hive.openBox<PlaylistEntry>(playlistItems),
    ]);
  }
}
