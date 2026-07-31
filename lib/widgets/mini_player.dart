import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../app.dart';

class MiniPlayerWidget extends ConsumerWidget {
  const MiniPlayerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final video = state.currentVideo;
    if (video == null || !state.isMinimized) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => ref.read(playerProvider.notifier).expand(),
      child: Container(
        height: 64,
        color: const Color(0xFF1C1C1E),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: state.duration.inMilliseconds > 0
                  ? state.position.inMilliseconds / state.duration.inMilliseconds
                  : 0,
              backgroundColor: Colors.white10,
              color: Colors.red,
              minHeight: 2,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: video.thumbnailUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: video.thumbnailUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: Colors.grey[800]),
                              )
                            : Container(
                                color: Colors.grey[800],
                                child: const Icon(Icons.music_note, color: Colors.white38),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            video.platform.isNotEmpty ? video.platform : 'YouTube',
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        final notifier = ref.read(playerProvider.notifier);
                        final webView = MrPlayApp.webViewKey.currentState;
                        if (state.isPlaying) {
                          notifier.pause();
                          webView?.controlVideo('pause');
                        } else {
                          notifier.resume();
                          webView?.controlVideo('play');
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                      onPressed: () => ref.read(playerProvider.notifier).dismiss(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
