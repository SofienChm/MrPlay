import 'package:hive_flutter/hive_flutter.dart';
import '../models/playlist.dart';

/// User playlists persisted in their own Hive box. A playlist stores items
/// (videos/music) with the platform URL needed to resume playback.
class PlaylistRepository {
  static const String _boxName = 'playlists';
  static Box<Playlist>? _box;

  static Future<Box<Playlist>> get box async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox<Playlist>(_boxName);
    return _box!;
  }

  static Future<List<Playlist>> getAll() async {
    final b = await box;
    final list = b.values.toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  static Future<Playlist?> get(String id) async {
    final b = await box;
    return b.get(id);
  }

  static Future<Playlist> create(String name) async {
    final b = await box;
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    );
    await b.put(playlist.id, playlist);
    return playlist;
  }

  static Future<void> rename(String id, String name) async {
    final b = await box;
    final existing = b.get(id);
    if (existing == null) return;
    final updated = Playlist(
      id: existing.id,
      name: name,
      items: existing.items,
      createdAt: existing.createdAt,
    );
    await b.put(id, updated);
  }

  static Future<void> delete(String id) async {
    final b = await box;
    await b.delete(id);
  }

  /// Adds an item (deduped by item id) to the end of the playlist.
  static Future<bool> addItem(String playlistId, PlaylistItem item) async {
    final b = await box;
    final existing = b.get(playlistId);
    if (existing == null) return false;
    if (existing.items.any((i) => i.id == item.id)) return false;
    final reindexed = [
      for (var i = 0; i < existing.items.length; i++)
        existing.items[i].copyWith(sortIndex: i),
      item.copyWith(sortIndex: existing.items.length),
    ];
    final updated = Playlist(
      id: existing.id,
      name: existing.name,
      items: reindexed,
      createdAt: existing.createdAt,
    );
    await b.put(playlistId, updated);
    return true;
  }

  static Future<void> removeItem(String playlistId, String itemId) async {
    final b = await box;
    final existing = b.get(playlistId);
    if (existing == null) return;
    final remaining = existing.items.where((i) => i.id != itemId).toList();
    final reindexed = [
      for (var i = 0; i < remaining.length; i++)
        remaining[i].copyWith(sortIndex: i),
    ];
    final updated = Playlist(
      id: existing.id,
      name: existing.name,
      items: reindexed,
      createdAt: existing.createdAt,
    );
    await b.put(playlistId, updated);
  }

  /// Persists a new ordered item list for the playlist.
  static Future<void> reorder(String playlistId, List<PlaylistItem> ordered) async {
    final b = await box;
    final existing = b.get(playlistId);
    if (existing == null) return;
    final reindexed = [
      for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(sortIndex: i),
    ];
    final updated = Playlist(
      id: existing.id,
      name: existing.name,
      items: reindexed,
      createdAt: existing.createdAt,
    );
    await b.put(playlistId, updated);
  }

  static Future<void> clear() async {
    final b = await box;
    await b.clear();
  }
}