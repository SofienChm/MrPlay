import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/favorite_video.dart';

class FavoritesRepository {
  static const String _boxName = 'favorites';
  late Box<String> _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  List<FavoriteVideo> getAll() {
    final videos = _box.values.map((json) {
      try {
        return FavoriteVideo.fromJson(jsonDecode(json) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<FavoriteVideo>().toList();
    videos.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return videos;
  }

  Future<void> add(FavoriteVideo video) async {
    // Avoid duplicates by checking if the same URL + title already exists
    final existing = _box.values.any((json) {
      try {
        final data = jsonDecode(json) as Map<String, dynamic>;
        return data['platformUrl'] == video.platformUrl && data['title'] == video.title;
      } catch (_) {
        return false;
      }
    });
    if (!existing) {
      await _box.put(video.id, jsonEncode(video.toJson()));
    }
  }

  Future<void> remove(String id) async {
    await _box.delete(id);
  }

  bool isFavorite(String id) {
    return _box.containsKey(id);
  }

  Future<void> clearAll() async {
    await _box.clear();
  }

  int get count => _box.length;
}
