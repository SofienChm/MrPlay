import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hub_backgrounds.dart';
import '../../data/models/playlist.dart';
import '../../data/models/playlist_item.dart';
import '../../data/models/queue_item.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../app.dart';

/// Shows a single playlist's entries. "Play all" (or tapping an entry) loads
/// the URLs one-by-one via the app's playback queue.
class PlaylistDetailPage extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  List<PlaylistItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await PlaylistRepository.getItems(widget.playlist.id);
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  QueueItem _queueItemOf(PlaylistItem item) => QueueItem(
        id: item.id,
        title: item.title,
        thumbnailUrl: item.thumbnailUrl,
        platformUrl: item.platformUrl,
        platformName: item.platformName,
      );

  void _playFrom(int index) {
    final tail = _items.sublist(index);
    // Pop back to the app's home Stack (webview layer) and start playback.
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.isFirst);
    MrPlayApp.webViewKey.currentState
        ?.playSequentially(tail.map(_queueItemOf).toList());
  }

  Future<void> _removeItem(PlaylistItem item) async {
    await PlaylistRepository.removeItem(widget.playlist.id, item.id);
    _load();
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Clear "${widget.playlist.name}"?'),
        content: const Text('All entries will be removed from this playlist.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await PlaylistRepository.clearItems(widget.playlist.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MrPlayApp.hubBackgroundNotifier,
      builder: (context, background, _) => Theme(
        data: AppTheme.darkTheme(Theme.of(context).colorScheme.primary),
        child: Scaffold(
          appBar: AppBar(title: Text(widget.playlist.name)),
          body: Container(
            decoration: HubBackgrounds.decorationFor(background),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.playlist_add,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'Playlist is empty',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Use "Add to playlist" from the player menu',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => _playFrom(0),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Play all'),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              icon: const Icon(Icons.delete_sweep),
                              onPressed: _confirmClear,
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _items.length,
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 80,
                                      height: 45,
                                      child: item.thumbnailUrl.isNotEmpty
                                          ? Image.network(item.thumbnailUrl,
                                              fit: BoxFit.cover)
                                          : Container(
                                              color: Colors.grey,
                                              child: const Icon(
                                                  Icons.play_circle,
                                                  color: Colors.white),
                                            ),
                                    ),
                                  ),
                                  title: Text(item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(item.platformName, maxLines: 1),
                                  trailing: IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline),
                                    onPressed: () => _removeItem(item),
                                  ),
                                  onTap: () => _playFrom(index),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}
