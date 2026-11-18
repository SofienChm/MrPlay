import 'package:flutter/material.dart';
import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hub_backgrounds.dart';
import '../../data/models/playlist.dart';
import '../../data/models/queue_item.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/queue_repository.dart';

/// Shows the items of a single playlist. Tapping an item starts playback and
/// fills the playback queue with the remaining items so they play one by one.
class PlaylistDetailPage extends StatefulWidget {
  final String playlistId;

  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  Playlist? _playlist;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final playlist = await PlaylistRepository.get(widget.playlistId);
    if (mounted) {
      setState(() {
        _playlist = playlist;
        _isLoading = false;
      });
    }
  }

  Future<void> _play(int index) async {
    final playlist = _playlist;
    if (playlist == null) return;
    if (playlist.items.isEmpty) return;
    // Replace the playback queue with the playlist from this item onward, so
    // the webview's auto-advance loads each URL one by one.
    final remaining = playlist.items.skip(index).toList();
    await QueueRepository.clear();
    for (final item in remaining) {
      await QueueRepository.add(
        QueueItem(
          id: item.id,
          title: item.title,
          thumbnailUrl: item.thumbnailUrl,
          platformUrl: item.platformUrl,
          platformName: item.platformName,
        ),
      );
    }
    final target = remaining.first;
    MrPlayApp.webViewKey.currentState?.loadUrl(target.platformUrl);
    // Surface the app again so the just-opened video/music is visible instead
    // of playing hidden underneath the playlist, like Watch Later does.
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _removeItem(PlaylistItem item) async {
    await PlaylistRepository.removeItem(widget.playlistId, item.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MrPlayApp.hubBackgroundNotifier,
      builder: (context, background, _) => Theme(
        data: AppTheme.darkTheme(Theme.of(context).colorScheme.primary),
        child: Scaffold(
          appBar: AppBar(title: Text(_playlist?.name ?? 'Playlist')),
          body: Container(
            decoration: HubBackgrounds.decorationFor(background),
            child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlist == null
              ? const Center(child: Text('Playlist not found'))
              : _playlist!.items.isEmpty
                  ? const Center(
                      child: Text(
                        'No items yet\n\nTap "Add to playlist" on any video or music',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ReorderableListView.builder(
                      itemCount: _playlist!.items.length,
                      onReorder: _onReorder,
                      itemBuilder: (context, index) {
                        final item = _playlist!.items[index];
                        return ListTile(
                          key: ValueKey(item.id),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 80,
                              height: 45,
                              child: item.thumbnailUrl.isNotEmpty
                                  ? Image.network(
                                      item.thumbnailUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: Colors.grey,
                                        child: const Icon(Icons.music_note,
                                            color: Colors.white),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey,
                                      child: const Icon(Icons.play_circle,
                                          color: Colors.white),
                                    ),
                            ),
                          ),
                          title: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item.platformName.isEmpty
                                ? 'Web'
                                : item.platformName,
                            maxLines: 1,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => _removeItem(item),
                          ),
                          onTap: () => _play(index),
                        );
                      },
                    ),
          ),
        ),
      ),
    );
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final playlist = _playlist;
    if (playlist == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final items = List<PlaylistItem>.of(playlist.items);
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    await PlaylistRepository.reorder(playlist.id, items);
    _load();
  }
}