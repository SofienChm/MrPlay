import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/models.dart';
import 'widgets.dart';

class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Playback Queue')),
        body: const QueueList(),
      );
}

/// Reorderable "play next" queue.
class QueueList extends ConsumerWidget {
  const QueueList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncList<MediaItem>(
      value: ref.watch(queueProvider),
      builder: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.queue_music,
            title: 'Your queue is empty',
            message: 'Add videos from the player or a shared link. They play one after another.',
          );
        }
        return Column(
          children: [
            _QueueHeader(count: items.length),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: items.length,
                onReorder: (oldIndex, newIndex) => _reorder(ref, items, oldIndex, newIndex),
                itemBuilder: (context, i) => _QueueTile(key: ValueKey(items[i].id), item: items[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  void _reorder(WidgetRef ref, List<MediaItem> items, int oldIndex, int newIndex) {
    final ordered = [...items];
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, moved);
    fireAndForget(ref.read(queueRepositoryProvider).replaceAll(ordered));
  }
}

class _QueueHeader extends ConsumerWidget {
  const _QueueHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
        child: Row(
          children: [
            Expanded(child: Text('$count up next', style: Theme.of(context).textTheme.titleSmall)),
            IconButton(
              tooltip: 'Clear queue',
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                final ok = await confirm(context, title: 'Clear queue?', action: 'Clear');
                if (ok) await ref.read(queueRepositoryProvider).clear();
              },
            ),
          ],
        ),
      );
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
        leading: VideoThumbnail(url: item.thumbnailUrl, width: 80),
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(item.platform, maxLines: 1),
        trailing: IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => fireAndForget(ref.read(queueRepositoryProvider).remove(item.id)),
        ),
        onTap: () async {
          await ref.read(queueRepositoryProvider).remove(item.id);
          if (context.mounted) playUrl(context, ref, item.url);
        },
      );
}
