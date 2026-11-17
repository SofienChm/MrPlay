import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/palettes.dart';
import '../../data/models/models.dart';
import 'widgets.dart';

/// Lets the user add [video] to an existing playlist or a new one.
Future<void> showAddToPlaylistSheet(BuildContext context, Video video) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (sheetContext) => _AddToPlaylistSheet(video: video, hostContext: context),
    );

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.video, required this.hostContext});

  final Video video;

  /// Context of the page that opened the sheet; still mounted after the sheet
  /// closes, so dialogs and snackbars go there.
  final BuildContext hostContext;

  Future<void> _add(WidgetRef ref, Playlist playlist) async {
    final added = await ref.read(playlistRepositoryProvider).addVideo(playlist.id, video);
    if (!hostContext.mounted) return;
    showSnack(hostContext, added ? 'Added to "${playlist.name}"' : 'Already in "${playlist.name}"');
  }

  Future<void> _createAndAdd(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    final name = await promptText(hostContext, title: 'New playlist', action: 'Create');
    if (name == null) return;
    final playlist = await ref.read(playlistRepositoryProvider).create(name);
    await _add(ref, playlist);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).valueOrNull ?? const <Playlist>[];
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      decoration: const BoxDecoration(
        color: PlayerColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Add to playlist',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add, color: Colors.white70),
              title: const Text('New playlist', style: TextStyle(color: Colors.white)),
              onTap: () => _createAndAdd(context, ref),
            ),
            const Divider(color: Colors.white10, height: 1, indent: 56),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No playlists yet — create one first.', style: TextStyle(color: Colors.white54)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: const Icon(Icons.playlist_play, color: Colors.white70),
                    title: Text(
                      playlists[i].name,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      fireAndForget(_add(ref, playlists[i]));
                    },
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
