import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/link_resolver_service.dart';
import '../data/models/favorite_video.dart';
import '../data/models/queue_item.dart';
import '../data/repositories/watch_later_repository.dart';
import '../data/repositories/queue_repository.dart';
import 'package:cached_network_image/cached_network_image.dart';

class LinkResolverSheet extends ConsumerStatefulWidget {
  final String url;

  const LinkResolverSheet({super.key, required this.url});

  @override
  ConsumerState<LinkResolverSheet> createState() => _LinkResolverSheetState();
}

class _LinkResolverSheetState extends ConsumerState<LinkResolverSheet> {
  ResolvedLink? _resolved;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final result = await LinkResolverService.instance.resolve(widget.url);
    if (mounted) {
      setState(() {
        _resolved = result;
        _loading = false;
      });
    }
  }

  Future<void> _addToQueue() async {
    if (_resolved == null) return;
    final r = _resolved!;
    final item = QueueItem(
      id: r.videoId,
      title: r.title,
      thumbnailUrl: r.thumbnailUrl,
      platformUrl: r.url,
      platformName: r.platform,
    );
    await QueueRepository.add(item);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to queue'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _addToWatchLater() async {
    if (_resolved == null) return;
    final r = _resolved!;
    await WatchLaterRepository.add(
      FavoriteVideo(
        id: r.videoId,
        title: r.title,
        channel: r.channel,
        thumbnailUrl: r.thumbnailUrl,
        platformUrl: r.url,
        addedAt: DateTime.now(),
      ),
    );
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Watch Later'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _downloadThumbnail() async {
    if (_resolved == null) return;
    final r = _resolved!;
    if (r.thumbnailUrl.isEmpty) return;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final request = await client.getUrl(Uri.parse(r.thumbnailUrl));
        final response = await request.close();
        if (response.statusCode == 200) {
          final bytes = await response.fold<List<int>>(
              <int>[], (prev, chunk) => prev..addAll(chunk));
          final dir = await Directory.systemTemp.createTemp('mrplay_thumb_');
          final file = File('${dir.path}/thumbnail.jpg');
          await file.writeAsBytes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Thumbnail saved to ${file.path}')),
            );
          }
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download thumbnail')),
        );
      }
    }
  }

  void _shareCleanLink() {
    if (_resolved == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Link: ${_resolved!.url}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: _loading
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator(color: Colors.red)),
              )
            : _resolved == null
                ? SizedBox(
                    height: 200,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Could not resolve link',
                              style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 12),
                          Text(widget.url,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context, 'open');
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red),
                            child: const Text('Open anyway'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _buildResolved(),
      ),
    );
  }

  Widget _buildResolved() {
    final r = _resolved!;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 140,
                  height: 80,
                  child: r.thumbnailUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: r.thumbnailUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: Colors.grey[900]),
                          errorWidget: (_, __, ___) =>
                              Container(color: Colors.grey[900]),
                        )
                      : Container(color: Colors.grey[900]),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        r.platform,
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    if (r.channel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        r.channel,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 8),
          _ActionRow(
            icon: Icons.play_arrow,
            label: 'Play',
            color: Colors.red,
            onTap: () => Navigator.pop(context, 'play'),
          ),
          _ActionRow(
            icon: Icons.playlist_add,
            label: 'Add to Queue',
            onTap: _addToQueue,
          ),
          _ActionRow(
            icon: Icons.bookmark_border,
            label: 'Watch Later',
            onTap: _addToWatchLater,
          ),
          _ActionRow(
            icon: Icons.download,
            label: 'Download Thumbnail',
            onTap: _downloadThumbnail,
          ),
          _ActionRow(
            icon: Icons.share,
            label: 'Share Clean Link',
            onTap: _shareCleanLink,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: color ?? Colors.white70, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color ?? Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
