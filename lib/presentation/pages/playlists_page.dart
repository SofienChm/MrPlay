import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hub_backgrounds.dart';
import '../../data/models/playlist.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../app.dart';
import 'playlist_detail_page.dart';

/// Lists the user's playlists and lets them create new ones.
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
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreatePlaylistDialog(),
    );
    if (name != null && name.isNotEmpty) {
      await PlaylistRepository.create(name);
      _load();
    }
  }

  Future<void> _confirmDelete(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${playlist.name}"?'),
        content: const Text('This playlist and its entries will be removed.'),
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
                tooltip: 'New playlist',
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
                          children: [
                            const Icon(Icons.playlist_play,
                                size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text(
                              'No playlists yet',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _createPlaylist,
                              icon: const Icon(Icons.add),
                              label: const Text('Create playlist'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = _playlists[index];
                          return FutureBuilder<int>(
                            future: PlaylistRepository.itemCount(playlist.id),
                            builder: (context, snapshot) {
                              final count = snapshot.data ?? 0;
                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.playlist_play),
                                ),
                                title: Text(playlist.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  '$count ${count == 1 ? 'item' : 'items'}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _confirmDelete(playlist),
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PlaylistDetailPage(
                                        playlist: playlist,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
          ),
        ),
      ),
    );
  }
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'My playlist',
        ),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _nameController.text.trim()),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
