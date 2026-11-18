import 'package:flutter/material.dart';
import '../../data/models/playlist.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../models/video.dart';

/// Bottom sheet with the existing playlists + "New playlist" so the user can
/// save the current video/music into a playlist.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  Video video,
) async {
  final playlists = await PlaylistRepository.getAll();
  if (!context.mounted) return;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C1E),
    builder: (sheetContext) {
      final nameController = TextEditingController();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add to playlist',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (playlists.isNotEmpty)
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.queue_music,
                          color: Colors.white70,
                        ),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          '${playlist.items.length} item${playlist.items.length == 1 ? '' : 's'}',
                          style: const TextStyle(color: Colors.white38),
                        ),
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final added = await PlaylistRepository.addItem(
                            playlist.id,
                            PlaylistItem(
                              id: video.id.isEmpty ? video.videoUrl : video.id,
                              title: video.title,
                              thumbnailUrl: video.thumbnailUrl,
                              platformUrl: video.videoUrl,
                              platformName:
                                  video.platform.isEmpty ? 'Web' : video.platform,
                            ),
                          );
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                          messenger.showSnackBar(
                            SnackBar(
                              content:
                                  Text(added ? 'Added to playlist' : 'Already in playlist'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.add, color: Colors.red),
                title: TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'New playlist name',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _createAndAdd(
                    sheetContext,
                    context,
                    nameController,
                    video,
                  ),
                ),
                trailing: TextButton(
                  child: const Text('Create', style: TextStyle(color: Colors.red)),
                  onPressed: () => _createAndAdd(
                    sheetContext,
                    context,
                    nameController,
                    video,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _createAndAdd(
  BuildContext sheetContext,
  BuildContext context,
  TextEditingController controller,
  Video video,
) async {
  final name = controller.text.trim();
  if (name.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final playlist = await PlaylistRepository.create(name);
  await PlaylistRepository.addItem(
    playlist.id,
    PlaylistItem(
      id: video.id.isEmpty ? video.videoUrl : video.id,
      title: video.title,
      thumbnailUrl: video.thumbnailUrl,
      platformUrl: video.videoUrl,
      platformName: video.platform.isEmpty ? 'Web' : video.platform,
    ),
  );
  if (sheetContext.mounted) Navigator.pop(sheetContext);
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Added to playlist'),
      duration: Duration(seconds: 1),
    ),
  );
}