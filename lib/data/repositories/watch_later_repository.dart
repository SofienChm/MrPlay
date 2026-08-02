import 'package:hive_flutter/hive_flutter.dart';
import '../models/favorite_video.dart';

/// Watch Later queue. Reuses the [FavoriteVideo] model/adapter but stores
/// entries in a separate Hive box so the two lists stay independent.
class WatchLaterRepository {
  static const String _boxName = 'watch_later';
  static Box<FavoriteVideo>? _box;

  static Future<Box<FavoriteVideo>> get box async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox<FavoriteVideo>(_boxName);
    return _box!;
  }

  static Future<List<FavoriteVideo>> getAll() async {
    final b = await box;
    return b.values.toList().reversed.toList();
  }

  static Future<void> add(FavoriteVideo video) async {
    final b = await box;
    await b.put(video.id, video);
  }

  static Future<void> remove(String id) async {
    final b = await box;
    await b.delete(id);
  }

  static Future<bool> isQueued(String id) async {
    final b = await box;
    return b.containsKey(id);
  }

  static Future<void> clear() async {
    final b = await box;
    await b.clear();
  }
}
