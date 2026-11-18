import 'package:flutter/material.dart';
import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hub_backgrounds.dart';
import '../../data/models/playlist.dart';
import '../../data/repositories/playlist_repository.dart';
import 'playlist_detail_page.dart';

/// Hub entry point for user playlists: shows all playlists and lets the user
/// create new ones.
class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  List<Playlist> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final playlists = await PlaylistRepository.getAll();
    if (mounted) {
      setState(() {
        _playlists = playlists;
        _isLoading = false;
      });
    }
  }

  Future<void> _createPlaylist() async {
    final name = await _promptName(context);
    if (name == null || name.trim().isEmpty) return;
    await PlaylistRepository.create(name.trim());
    _load();
  }

  Future<void> _rename(Playlist playlist) async {
    final name = await _promptName(context, initial: playlist.name);
    if (name == null || name.trim().isEmpty) return;
    await PlaylistRepository.rename(playlist.id, name.trim());
    _load();
  }

  Future<void> _delete(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text(
            'This will remove "${playlist.name}" and all its items.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await PlaylistRepository.delete(playlist.id);
      _load();
    }
  }

  void _open(Playlist playlist) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
              settings: const RouteSettings(name: 'PlaylistDetail'),
              builder: (_) => PlaylistDetailPage(playlistId: playlist.id)),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MrPlayApp.hubBackgroundNotifier,
      builder: (context, background, _) => Theme(
        data: AppTheme.darkTheme(Theme.of(context).colorScheme.primary),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Playlists'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Create playlist',
                onPressed: _createPlaylist,
              ),
            ],
          ),
          body: Container(
            decoration: HubBackgrounds.decorationFor(background),
            child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.queue_music, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No playlists yet',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tap "Add to playlist" on any video or music',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    final count = playlist.items.length;
                    return ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.queue_music,
                            color: Colors.white70),
                      ),
                      title: Text(playlist.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('$count item${count == 1 ? '' : 's'}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'rename') _rename(playlist);
                          if (value == 'delete') _delete(playlist);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename')),
                          PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                      onTap: () => _open(playlist),
                    );
                  },
                ),
              ),
          ),
        ),
);
  }
}

/// Shared name dialog used by create + rename.
Future<String?> _promptName(BuildContext context, {String? initial}) async {
  final controller = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(initial == null ? 'New playlist' : 'Rename playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 50,
        decoration: const InputDecoration(
          hintText: 'Playlist name',
        ),
        onSubmitted: (value) => Navigator.pop(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Helper to start playing an item from a playlist and automatically continue
/// through the rest one by one by filling the playback queue.
Future<void> playPlaylistFromItem(BuildContext context,
    List<PlaylistItem> items, int startIndex) async {
  final target = items[startIndex];
  MrPlayApp.webViewKey.currentState?.loadUrl(target.platformUrl);
}