import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../app.dart';

class FullPlayerWidget extends ConsumerStatefulWidget {
  const FullPlayerWidget({super.key});

  @override
  ConsumerState<FullPlayerWidget> createState() => _FullPlayerWidgetState();
}

class _FullPlayerWidgetState extends ConsumerState<FullPlayerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(0, 1),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));
    _slideController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        ref.read(playerProvider.notifier).minimize();
        _slideController.reset();
      }
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final shouldMinimize =
        (details.primaryVelocity != null && details.primaryVelocity! > 500) ||
            _dragOffset > 150;
    if (shouldMinimize) {
      MrPlayApp.webViewKey.currentState?.enterPiP();
      _slideController.forward();
    } else {
      _slideController.reverse();
    }
    setState(() => _dragOffset = 0);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      if (_dragOffset < 0) _dragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    final video = state.currentVideo;
    if (video == null || state.isMinimized) return const SizedBox.shrink();

    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final progress = (_dragOffset / screenHeight).clamp(0.0, 1.0);
    final translateY = _dragOffset * (1 - progress * 0.3);
    final scale = 1 - progress * 0.05;
    final opacity = 1 - progress;

    return SlideTransition(
      position: _slideAnimation,
      child: GestureDetector(
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Container(
          color: Colors.black.withValues(alpha: 0.95 * opacity),
          child: Stack(
            children: [
              Transform.translate(
                offset: Offset(0, translateY),
                child: Transform.scale(
                  scale: scale,
                  child: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(top: topPadding + 20),
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 3,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.grey[600],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: video.thumbnailUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: video.thumbnailUrl,
                                      fit: BoxFit.contain,
                                      placeholder: (_, __) => Container(
                                        color: Colors.black,
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                                          ),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey[900],
                                      child: const Center(
                                        child: Icon(Icons.play_circle, color: Colors.white38, size: 64),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  video.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  video.platform.isNotEmpty ? video.platform : 'YouTube',
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: Colors.red,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.red,
                              overlayColor: Colors.red.withValues(alpha: 0.2),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: state.duration.inMilliseconds > 0
                                  ? state.position.inMilliseconds /
                                      state.duration.inMilliseconds
                                  : 0,
                              onChanged: (value) {
                                final pos = Duration(
                                  milliseconds: (value * state.duration.inMilliseconds).round(),
                                );
                                ref.read(playerProvider.notifier).seekTo(pos);
                                MrPlayApp.webViewKey.currentState
                                    ?.controlVideo('seek', position: pos.inMilliseconds / 1000.0);
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(state.position),
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                                Text(
                                  _formatDuration(state.duration),
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                iconSize: 48,
                                icon: Icon(
                                  state.isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
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
                            ],
                          ),
                          const Spacer(),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: topPadding + 4,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => ref.read(playerProvider.notifier).dismiss(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$minutes:$seconds';
  }
}
