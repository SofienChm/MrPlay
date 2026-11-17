import 'dart:async';

import 'package:hive/hive.dart';

import '../local/hive_adapters.dart';
import '../models/models.dart';

/// Emits the current value, then again after every change of [box].
Stream<T> _watchBox<T>(Box<Object?> box, T Function() read) async* {
  yield read();
  await for (final _ in box.watch()) {
    yield read();
  }
}

/// Favorites or Watch Later (same shape, separate boxes).
class SavedVideoRepository {
  SavedVideoRepository(this._box);

  final Box<SavedVideo> _box;

  /// Newest first.
  List<SavedVideo> all() => _box.values.toList().reversed.toList();

  Stream<List<SavedVideo>> watch() => _watchBox(_box, all);

  bool contains(String id) => _box.containsKey(id);

  Future<void> add(SavedVideo video) => _box.put(video.id, video);

  Future<void> remove(String id) => _box.delete(id);

  Future<void> clear() => _box.clear();

  /// Adds when missing, removes when present. Returns the new saved state.
  Future<bool> toggle(Video video) async {
    final saved = SavedVideo.fromVideo(video);
    if (contains(saved.id)) {
      await remove(saved.id);
      return false;
    }
    await add(saved);
    return true;
  }
}

class ShortcutRepository {
  ShortcutRepository(this._box);

  final Box<Shortcut> _box;

  List<Shortcut> all() => _box.values.toList()..sort((a, b) => a.addedAt.compareTo(b.addedAt));

  Stream<List<Shortcut>> watch() => _watchBox(_box, all);

  Future<void> add({required String name, required String url}) {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    return _box.put(id, Shortcut(id: id, name: name, url: url, addedAt: now));
  }

  Future<void> remove(String id) => _box.delete(id);
}

/// Cross-platform "play next" queue, advanced when a video ends.
class QueueRepository {
  QueueRepository(this._box);

  final Box<MediaItem> _box;

  List<MediaItem> all() => _box.values.toList()..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  Stream<List<MediaItem>> watch() => _watchBox(_box, all);

  Future<void> add(MediaItem item) => _box.put(item.id, item.copyWith(sortIndex: _box.length));

  /// Inserts at the front ("Play next").
  Future<void> addNext(MediaItem item) => replaceAll([item, ...all().where((i) => i.id != item.id)]);

  Future<void> remove(String id) => _box.delete(id);

  /// Removes and returns the first item, or null when the queue is empty.
  Future<MediaItem?> takeNext() async {
    final items = all();
    if (items.isEmpty) return null;
    await _box.delete(items.first.id);
    return items.first;
  }

  /// Persists [ordered] as the whole queue, re-indexed.
  Future<void> replaceAll(List<MediaItem> ordered) async {
    await _box.clear();
    await _box.putAll({
      for (var i = 0; i < ordered.length; i++) ordered[i].id: ordered[i].copyWith(sortIndex: i),
    });
  }

  Future<void> clear() => _box.clear();
}

class PlaylistRepository {
  PlaylistRepository(this._playlists, this._entries);

  final Box<Playlist> _playlists;
  final Box<PlaylistEntry> _entries;

  List<Playlist> all() => _playlists.values.toList()..sort((a, b) => a.addedAt.compareTo(b.addedAt));

  Stream<List<Playlist>> watch() => _watchBox(_playlists, all);

  List<MediaItem> items(String playlistId) => _entries.values
      .map((e) => e.item)
      .where((i) => i.playlistId == playlistId)
      .toList()
    ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  Stream<List<MediaItem>> watchItems(String playlistId) =>
      _watchBox(_entries, () => items(playlistId));

  Future<Playlist> create(String name) async {
    final now = DateTime.now();
    final playlist = Playlist(id: now.millisecondsSinceEpoch.toString(), name: name, addedAt: now);
    await _playlists.put(playlist.id, playlist);
    return playlist;
  }

  Future<void> rename(Playlist playlist, String name) =>
      _playlists.put(playlist.id, Playlist(id: playlist.id, name: name, addedAt: playlist.addedAt));

  Future<void> delete(String id) async {
    await _playlists.delete(id);
    await clearItems(id);
  }

  /// Adds [video] to the playlist. Returns false when it is already there.
  Future<bool> addVideo(String playlistId, Video video) async {
    final item = MediaItem.fromVideo(video, playlistId: playlistId);
    if (_entries.containsKey(item.id)) return false;
    await _entries.put(item.id, PlaylistEntry(item.copyWith(sortIndex: items(playlistId).length)));
    return true;
  }

  Future<void> removeItem(MediaItem item) => _entries.delete(item.id);

  Future<void> clearItems(String playlistId) => _entries.deleteAll(
        _entries.keys.where((k) => k is String && k.startsWith('$playlistId::')).toList(),
      );
}
