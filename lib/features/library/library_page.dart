import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/models.dart';
import '../../data/repositories/library_repositories.dart';
import 'queue_page.dart';
import 'widgets.dart';

/// Favorites, Watch Later and the playback queue.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        initialIndex: initialTab.clamp(0, 2),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Library'),
            bottom: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: [
                Tab(icon: Icon(Icons.favorite), text: 'Favorites'),
                Tab(icon: Icon(Icons.bookmark), text: 'Watch Later'),
                Tab(icon: Icon(Icons.queue_music), text: 'Queue'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _SavedVideoList(
                listProvider: favoritesProvider,
                repositoryProvider: favoritesRepositoryProvider,
                emptyIcon: Icons.favorite_border,
                emptyTitle: 'No favorites yet',
                emptyMessage: 'Tap the heart in the player to save a video here.',
              ),
              _SavedVideoList(
                listProvider: watchLaterProvider,
                repositoryProvider: watchLaterRepositoryProvider,
                emptyIcon: Icons.bookmark_border,
                emptyTitle: 'Nothing to watch later',
                emptyMessage: 'Bookmark a video from the player or a shared link.',
              ),
              const QueueList(),
            ],
          ),
        ),
      );
}

class _SavedVideoList extends ConsumerWidget {
  const _SavedVideoList({
    required this.listProvider,
    required this.repositoryProvider,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final StreamProvider<List<SavedVideo>> listProvider;
  final Provider<SavedVideoRepository> repositoryProvider;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncList<SavedVideo>(
      value: ref.watch(listProvider),
      builder: (videos) {
        if (videos.isEmpty) {
          return EmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage);
        }
        final repo = ref.read(repositoryProvider);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${videos.length} videos', style: Theme.of(context).textTheme.titleSmall),
                  ),
                  IconButton(
                    tooltip: 'Clear all',
                    icon: const Icon(Icons.delete_sweep),
                    onPressed: () async {
                      final ok = await confirm(context, title: 'Clear all?', message: 'This cannot be undone.', action: 'Clear');
                      if (ok) await repo.clear();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: videos.length,
                itemBuilder: (context, i) => _SavedVideoTile(video: videos[i], onRemove: () => repo.remove(videos[i].id)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SavedVideoTile extends ConsumerWidget {
  const _SavedVideoTile({required this.video, required this.onRemove});

  final SavedVideo video;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Dismissible(
        key: ValueKey(video.id),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => fireAndForget(onRemove()),
        child: ListTile(
          leading: VideoThumbnail(url: video.thumbnailUrl, width: 80),
          title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(video.channel, maxLines: 1),
          trailing: IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => fireAndForget(onRemove()),
          ),
          onTap: () => playUrl(context, ref, video.url),
        ),
      );
}
