import 'package:hive_flutter/hive_flutter.dart';
import '../models/playlist.dart';
import '../models/playlist_item.dart';

/// User playlists. Playlists are stored in the `playlists` box and their
/// entries in `playlist_items` (keyed by `"$playlistId::$videoId"`).
class PlaylistRepository {
  static const String _playlistsBoxName = 'playlists';
  static const String _itemsBoxName = 'playlist_items';
  static Box<Playlist>? _playlistsBox;
  static Box<PlaylistItem>? _itemsBox;

  static Future<Box<Playlist>> get playlistsBox async {
    if (_playlistsBox != null && _playlistsBox!.isOpen) return _playlistsBox!;
    _playlistsBox = await Hive.openBox<Playlist>(_playlistsBoxName);
    return _playlistsBox!;
  }

  static Future<Box<PlaylistItem>> get itemsBox async {
    if (_itemsBox != null && _itemsBox!.isOpen) return _itemsBox!;
    _itemsBox = await Hive.openBox<PlaylistItem>(_itemsBoxName);
    return _itemsBox!;
  }

  static Future<List<Playlist>> getAll() async {
    final b = await playlistsBox;
    final list = b.values.toList();
    list.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return list;
  }

  static Future<Playlist> create(String name) async {
    final b = await playlistsBox;
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      addedAt: DateTime.now(),
    );
    await b.put(playlist.id, playlist);
    return playlist;
  }

  static Future<void> rename(String id, String name) async {
    final b = await playlistsBox;
    final existing = b.get(id);
    if (existing == null) return;
    await b.put(
      id,
      Playlist(id: existing.id, name: name, addedAt: existing.addedAt),
    );
  }

  static Future<void> delete(String id) async {
    final pb = await playlistsBox;
    await pb.delete(id);
    // Drop the playlist's entries too.
    final ib = await itemsBox;
    final toDelete = ib.keys
        .where((k) => (k as String).startsWith('$id::'))
        .toList();
    if (toDelete.isNotEmpty) await ib.deleteAll(toDelete);
  }

  static Future<List<PlaylistItem>> getItems(String playlistId) async {
    final b = await itemsBox;
    final items = b.values
        .where((i) => i.playlistId == playlistId)
        .toList();
    items.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    return items;
  }

  static Future<int> itemCount(String playlistId) async {
    final items = await getItems(playlistId);
    return items.length;
  }

  static Future<bool> contains(String playlistId, String videoId) async {
    final b = await itemsBox;
    return b.containsKey('$playlistId::$videoId');
  }

  /// Appends an entry to a playlist. Dedupes by video id (same video added
  /// twice to the same playlist is a no-op).
  static Future<bool> addItem(String playlistId, PlaylistItem item) async {
    final b = await itemsBox;
    final existing = await getItems(playlistId);
    if (existing.any((i) => i.id == item.id)) return false;
    final entry = item.copyWith(sortIndex: existing.length);
    await b.put(entry.id, entry);
    return true;
  }

  static Future<void> removeItem(String playlistId, String itemId) async {
    final b = await itemsBox;
    await b.delete('$playlistId::$itemId');
  }

  static Future<void> clearItems(String playlistId) async {
    final b = await itemsBox;
    final toDelete = b.keys
        .where((k) => (k as String).startsWith('$playlistId::'))
        .toList();
    if (toDelete.isNotEmpty) await b.deleteAll(toDelete);
  }
}
