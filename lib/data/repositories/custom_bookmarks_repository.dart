import 'package:hive_flutter/hive_flutter.dart';
import '../models/custom_bookmark.dart';

class CustomBookmarksRepository {
  static const String _boxName = 'custom_bookmarks';
  static Box<CustomBookmark>? _box;

  static Future<Box<CustomBookmark>> get box async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox<CustomBookmark>(_boxName);
    return _box!;
  }

  static Future<List<CustomBookmark>> getAll() async {
    final b = await box;
    final list = b.values.toList();
    list.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return list;
  }

  static Future<void> add(CustomBookmark bookmark) async {
    final b = await box;
    await b.put(bookmark.id, bookmark);
  }

  static Future<void> remove(String id) async {
    final b = await box;
    await b.delete(id);
  }
}
