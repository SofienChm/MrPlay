import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/platforms.dart';
import '../../data/models/models.dart';
import 'widgets.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final hasEntries = history.valueOrNull?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch History'),
        actions: [
          if (hasEntries)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: 'Clear watch history?',
                  message: 'This will remove all watched videos from your history.',
                  action: 'Clear',
                );
                if (ok) await ref.read(historyRepositoryProvider).clear();
              },
            ),
        ],
      ),
      body: AsyncList<HistoryEntry>(
        value: history,
        builder: (entries) {
          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icons.history_rounded,
              title: 'No watch history',
              message: 'Videos you watch in the last 15 days appear here.',
            );
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) => _HistoryTile(entry: entries[i]),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primary.withValues(alpha: 0.15),
        child: Icon(Platforms.iconFor(entry.platform), color: scheme.primary),
      ),
      title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${entry.platform} · ${relativeTime(entry.watchedAt)}', maxLines: 1),
      onTap: () => playUrl(context, ref, entry.url),
    );
  }
}

/// "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago".
String relativeTime(DateTime time, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays} days ago';
}
