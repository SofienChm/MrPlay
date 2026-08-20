import 'package:flutter/material.dart';
import '../../app.dart';
import '../../data/models/queue_item.dart';
import '../../data/repositories/queue_repository.dart';

/// Full-screen queue manager (opened from the full player).
class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Playback Queue')),
      body: const QueueListView(),
    );
  }
}

/// Reorderable queue list. Tapping an item plays it (and removes it from the
/// queue). Reused by the Library tab and the QueuePage.
class QueueListView extends StatefulWidget {
  const QueueListView({super.key});

  @override
  State<QueueListView> createState() => _QueueListViewState();
}

class _QueueListViewState extends State<QueueListView> {
  List<QueueItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await QueueRepository.getAll();
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = List<QueueItem>.of(_items);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    await QueueRepository.reorder(reordered);
    _load();
  }

  Future<void> _playItem(QueueItem item) async {
    await QueueRepository.remove(item.id);
    if (!mounted) return;
    // Pop any full-screen route so the app's home Stack (webview + video tab)
    // is visible, then open/play the video in the second tab.
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.isFirst);
    MrPlayApp.webViewKey.currentState?.loadUrl(item.platformUrl);
    _load();
  }

  Future<void> _removeItem(QueueItem item) async {
    await QueueRepository.remove(item.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.playlist_play, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Queue is empty',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Use "Play next" or "Add to queue" in the player',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              await QueueRepository.clear();
              _load();
            },
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: _items.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final item = _items[index];
              return ListTile(
                key: ValueKey(item.id),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 80,
                    height: 45,
                    child: item.thumbnailUrl.isNotEmpty
                        ? Image.network(item.thumbnailUrl, fit: BoxFit.cover)
                        : Container(
                            color: Colors.grey,
                            child: const Icon(Icons.play_circle,
                                color: Colors.white),
                          ),
                  ),
                ),
                title: Text(item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(item.platformName, maxLines: 1),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => _removeItem(item),
                ),
                onTap: () => _playItem(item),
              );
            },
          ),
        ),
      ],
    );
  }
}
