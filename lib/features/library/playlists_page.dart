import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/models.dart';
import 'playlist_detail_page.dart';
import 'widgets.dart';

class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await promptText(context, title: 'New playlist', action: 'Create');
    if (name != null) await ref.read(playlistRepositoryProvider).create(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(
          title: const Text('Playlists'),
          actions: [
            IconButton(
              tooltip: 'New playlist',
              icon: const Icon(Icons.add),
              onPressed: () => _create(context, ref),
            ),
          ],
        ),
        body: AsyncList<Playlist>(
          value: ref.watch(playlistsProvider),
          builder: (playlists) {
            if (playlists.isEmpty) {
              return EmptyState(
                icon: Icons.playlist_play,
                title: 'No playlists yet',
                message: 'Group videos from any platform, then play them in order.',
                action: FilledButton.icon(
                  onPressed: () => _create(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Create playlist'),
                ),
              );
            }
            return ListView.builder(
              itemCount: playlists.length,
              itemBuilder: (context, i) => _PlaylistTile(playlist: playlists[i]),
            );
          },
        ),
      );
}

enum _PlaylistAction { rename, delete }

class _PlaylistTile extends ConsumerWidget {
  const _PlaylistTile({required this.playlist});

  final Playlist playlist;

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await promptText(context, title: 'Rename playlist', initial: playlist.name);
    if (name != null && name != playlist.name) {
      await ref.read(playlistRepositoryProvider).rename(playlist, name);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Delete "${playlist.name}"?',
      message: 'This playlist and its entries will be removed.',
    );
    if (ok) await ref.read(playlistRepositoryProvider).delete(playlist.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(playlistItemsProvider(playlist.id)).valueOrNull?.length ?? 0;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.playlist_play)),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(count == 1 ? '1 video' : '$count videos'),
      trailing: PopupMenuButton<_PlaylistAction>(
        onSelected: (action) => switch (action) {
          _PlaylistAction.rename => _rename(context, ref),
          _PlaylistAction.delete => _delete(context, ref),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: _PlaylistAction.rename, child: Text('Rename')),
          PopupMenuItem(value: _PlaylistAction.delete, child: Text('Delete')),
        ],
      ),
      onLongPress: () => _rename(context, ref),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlaylistDetailPage(playlist: playlist)),
      ),
    );
  }
}
