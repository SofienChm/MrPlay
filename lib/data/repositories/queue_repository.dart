import 'package:hive_flutter/hive_flutter.dart';
import '../models/queue_item.dart';

/// Cross-platform playback queue, persisted in its own Hive box.
class QueueRepository {
  static const String _boxName = 'playback_queue';
  static Box<QueueItem>? _box;

  static Future<Box<QueueItem>> get box async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox<QueueItem>(_boxName);
    return _box!;
  }

  static Future<List<QueueItem>> getAll() async {
    final b = await box;
    final list = b.values.toList();
    list.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    return list;
  }

  /// Appends an item to the end of the queue.
  static Future<void> add(QueueItem item) async {
    final b = await box;
    final items = await getAll();
    final queued = item.copyWith(sortIndex: items.length);
    await b.put(queued.id, queued);
  }

  /// Inserts an item at the front of the queue ("Play next").
  static Future<void> addNext(QueueItem item) async {
    final b = await box;
    final items = await getAll();
    final updated = <QueueItem>[
      item.copyWith(sortIndex: 0),
      for (final existing in items) existing.copyWith(sortIndex: existing.sortIndex + 1),
    ];
    await b.clear();
    await b.putAll({for (final i in updated) i.id: i});
  }

  static Future<void> remove(String id) async {
    final b = await box;
    await b.delete(id);
  }

  /// Re-applies sort indices from the given (already ordered) list.
  static Future<void> reorder(List<QueueItem> ordered) async {
    final b = await box;
    final reindexed = [
      for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(sortIndex: i),
    ];
    await b.clear();
    await b.putAll({for (final item in reindexed) item.id: item});
  }

  static Future<void> clear() async {
    final b = await box;
    await b.clear();
  }
}
