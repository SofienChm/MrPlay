import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/theme/palettes.dart';
import '../../data/models/models.dart';
import '../player/playback_engine.dart';
import 'link_resolver.dart';

/// Bottom sheet for a link shared into MrPlay: play it, queue it, save it.
Future<void> showLinkSheet(BuildContext context, String url) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (_) => _LinkSheet(key: ValueKey(url), url: url),
    );

class _LinkSheet extends ConsumerStatefulWidget {
  const _LinkSheet({super.key, required this.url});

  final String url;

  @override
  ConsumerState<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends ConsumerState<_LinkSheet> {
  late final Future<ResolvedLink> _future = ref.read(linkResolverProvider).resolve(widget.url);

  Video _videoOf(ResolvedLink r) => Video(
        id: r.videoId.isEmpty ? r.url : r.videoId,
        title: r.title,
        url: r.url,
        thumbnailUrl: r.thumbnailUrl,
        platform: r.platform,
      );

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 1)),
    );
  }

  void _play(String url) {
    final navigator = Navigator.of(context);
    ref.read(playbackEngineProvider).loadUrl(url);
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _addToQueue(ResolvedLink r) async {
    await ref.read(queueRepositoryProvider).add(MediaItem.fromVideo(_videoOf(r)));
    _snack('Added to queue');
  }

  Future<void> _watchLater(ResolvedLink r) async {
    await ref.read(watchLaterRepositoryProvider).add(SavedVideo.fromVideo(_videoOf(r)));
    _snack('Saved to Watch Later');
  }

  Future<void> _downloadThumbnail(ResolvedLink r) async {
    if (r.thumbnailUrl.isEmpty) return _snack('No thumbnail available');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final response = await (await client.getUrl(Uri.parse(r.thumbnailUrl))).close();
      if (response.statusCode != HttpStatus.ok) throw HttpException('HTTP ${response.statusCode}');
      final dir = await getApplicationDocumentsDirectory();
      final name = r.videoId.isEmpty ? DateTime.now().millisecondsSinceEpoch : r.videoId;
      final file = File('${dir.path}/thumbnail_$name.jpg');
      await response.pipe(file.openWrite());
      _snack('Thumbnail saved');
    } on Exception {
      _snack('Failed to download thumbnail');
    } finally {
      client.close(force: true);
    }
  }

  void _share(ResolvedLink r) {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
    unawaited(Share.share(r.url, subject: r.title, sharePositionOrigin: origin));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PlayerColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: FutureBuilder<ResolvedLink>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
              }
              final r = snapshot.data;
              if (r == null) return _failure();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Handle(),
                  _Header(link: r),
                  const SizedBox(height: 12),
                  _Action(icon: Icons.play_arrow, label: 'Play', onTap: () => _play(r.url)),
                  _Action(icon: Icons.playlist_add, label: 'Add to Queue', onTap: () => _addToQueue(r)),
                  _Action(icon: Icons.bookmark_border, label: 'Watch Later', onTap: () => _watchLater(r)),
                  _Action(icon: Icons.download, label: 'Download Thumbnail', onTap: () => _downloadThumbnail(r)),
                  _Action(icon: Icons.share, label: 'Share Clean Link', onTap: () => _share(r)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _failure() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Handle(),
          const Text('Could not resolve link', style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 8),
          Text(widget.url, style: const TextStyle(color: Colors.white54), maxLines: 2),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => _play(widget.url), child: const Text('Open anyway')),
        ],
      );
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.link});

  final ResolvedLink link;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 120,
            height: 68,
            child: link.thumbnailUrl.isEmpty
                ? Container(color: Colors.white10, child: const Icon(Icons.link, color: Colors.white38))
                : CachedNetworkImage(imageUrl: link.thumbnailUrl, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                link.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              if (link.channel.isNotEmpty)
                Text(link.channel, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Colors.white70),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        onTap: onTap,
      );
}
