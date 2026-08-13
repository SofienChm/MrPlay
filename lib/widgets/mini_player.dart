import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../app.dart';

class MiniPlayerWidget extends ConsumerStatefulWidget {
  const MiniPlayerWidget({super.key});

  @override
  ConsumerState<MiniPlayerWidget> createState() => _MiniPlayerWidgetState();
}

class _MiniPlayerWidgetState extends ConsumerState<MiniPlayerWidget> {
  double _dragOffset = 0;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      if (_dragOffset < 0) _dragOffset = 0;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final shouldEnterPiP =
        (details.primaryVelocity != null && details.primaryVelocity! > 400) ||
            _dragOffset > 150;
    if (shouldEnterPiP) {
      MrPlayApp.webViewKey.currentState?.enterPiP();
    }
    setState(() => _dragOffset = 0);
  }

  void _seekMini(double dx, double width, Duration duration) {
    if (duration <= Duration.zero || width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    final pos = Duration(
      milliseconds: (fraction * duration.inMilliseconds).round(),
    );
    ref.read(playerProvider.notifier).seekTo(pos);
    MrPlayApp.webViewKey.currentState
        ?.controlVideo('seek', position: pos.inMilliseconds / 1000.0);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    final video = state.currentVideo;
    if (video == null || !state.isMinimized) return const SizedBox.shrink();

    // Visual feedback while dragging down towards PiP: follow the finger and
    // fade out so the gesture doesn't feel dead.
    final dragProgress = (_dragOffset / 200).clamp(0.0, 1.0);

    return Transform.translate(
      offset: Offset(0, _dragOffset * 0.6),
      child: Opacity(
        opacity: 1 - dragProgress * 0.7,
        child: GestureDetector(
          onTap: () {
            MrPlayApp.webViewKey.currentState?.exitPiP();
            ref.read(playerProvider.notifier).expand();
          },
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Container(
            height: 64,
            color: const Color(0xFF1C1C1E),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final progress = state.duration.inMilliseconds > 0
                        ? (state.position.inMilliseconds /
                                state.duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) =>
                          _seekMini(d.localPosition.dx, width, state.duration),
                      // Register a tap recognizer so tapping the bar seeks
                      // instead of bubbling up to the outer tap (expand).
                      onTapUp: (_) {},
                      onHorizontalDragUpdate: (d) =>
                          _seekMini(d.localPosition.dx, width, state.duration),
                      child: SizedBox(
                        height: 12,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  height: 2,
                                  width: width,
                                  color: Colors.white10,
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Container(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  height: 2,
                                  width: width * progress,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                                    placeholder: (_, __) =>
                                        Container(color: Colors.grey[800]),
                                  )
                                : Container(
                                    color: Colors.grey[800],
                                    child: const Icon(Icons.music_note,
                                        color: Colors.white38),
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
                                video.platform.isNotEmpty
                                    ? video.platform
                                    : 'YouTube',
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
                            state.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
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
                          icon: const Icon(Icons.close,
                              color: Colors.white54, size: 20),
                          onPressed: () {
                            MrPlayApp.webViewKey.currentState?.closePlayer();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
