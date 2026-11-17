import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/models.dart';
import '../player/playback_engine.dart';
import 'widgets.dart';

class PlaylistDetailPage extends ConsumerWidget {
  const PlaylistDetailPage({super.key, required this.playlist});

  final Playlist playlist;

  void _playFrom(BuildContext context, WidgetRef ref, List<MediaItem> items, int index) {
    fireAndForget(ref.read(playbackEngineProvider).playSequentially(items.sublist(index)));
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: Text(playlist.name)),
        body: AsyncList<MediaItem>(
          value: ref.watch(playlistItemsProvider(playlist.id)),
          builder: (items) {
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.playlist_add,
                title: 'This playlist is empty',
                message: 'Use "Add to Playlist" from the player options to add videos.',
              );
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => _playFrom(context, ref, items, 0),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play all'),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Clear playlist',
                        icon: const Icon(Icons.delete_sweep),
                        onPressed: () async {
                          final ok = await confirm(
                            context,
                            title: 'Clear "${playlist.name}"?',
                            message: 'All entries will be removed from this playlist.',
                            action: 'Clear',
                          );
                          if (ok) await ref.read(playlistRepositoryProvider).clearItems(playlist.id);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return ListTile(
                        leading: VideoThumbnail(url: item.thumbnailUrl, width: 80),
                        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(item.platform, maxLines: 1),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => fireAndForget(ref.read(playlistRepositoryProvider).removeItem(item)),
                        ),
                        onTap: () => _playFrom(context, ref, items, i),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      );
}
