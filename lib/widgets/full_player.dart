import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../models/video.dart';
import '../data/models/favorite_video.dart';
import '../data/models/queue_item.dart';
import '../data/repositories/favorites_repository.dart';
import '../data/repositories/watch_later_repository.dart';
import '../data/repositories/queue_repository.dart';
import '../services/sleep_timer_service.dart';
import '../presentation/pages/queue_page.dart';
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

  QueueItem _queueItemOf(Video video) => QueueItem(
        id: video.id,
        title: video.title,
        thumbnailUrl: video.thumbnailUrl,
        platformUrl: video.videoUrl,
        platformName: video.platform.isEmpty ? 'YouTube' : video.platform,
      );

  Future<void> _addToQueue() async {
    final video = ref.read(playerProvider).currentVideo;
    if (video == null) return;
    await QueueRepository.add(_queueItemOf(video));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to queue'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _playNext() async {
    final video = ref.read(playerProvider).currentVideo;
    if (video == null) return;
    await QueueRepository.addNext(_queueItemOf(video));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Will play next'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _openQueue() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QueuePage()),
    );
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
                                  ? (state.position.inMilliseconds /
                                          state.duration.inMilliseconds)
                                      .clamp(0.0, 1.0)
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.playlist_play, color: Colors.white70),
                                tooltip: 'Play next',
                                onPressed: _playNext,
                              ),
                              IconButton(
                                icon: const Icon(Icons.playlist_add, color: Colors.white70),
                                tooltip: 'Add to queue',
                                onPressed: _addToQueue,
                              ),
                              IconButton(
                                icon: const Icon(Icons.queue_music, color: Colors.white70),
                                tooltip: 'Open queue',
                                onPressed: _openQueue,
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
                child: Row(
                  children: [
                    const _SleepTimerButton(),
                    _WatchLaterButton(
                      key: ValueKey('wl_${video.id}'),
                      video: video,
                    ),
                    _FavoriteButton(
                      key: ValueKey(video.id),
                      video: video,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => ref.read(playerProvider.notifier).dismiss(),
                    ),
                  ],
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

class _FavoriteButton extends StatefulWidget {
  final Video video;

  const _FavoriteButton({super.key, required this.video});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _WatchLaterButton extends StatefulWidget {
  final Video video;

  const _WatchLaterButton({super.key, required this.video});

  @override
  State<_WatchLaterButton> createState() => _WatchLaterButtonState();
}

class _WatchLaterButtonState extends State<_WatchLaterButton> {
  bool? _isQueued;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final queued = await WatchLaterRepository.isQueued(widget.video.id);
    if (mounted) setState(() => _isQueued = queued);
  }

  Future<void> _toggle() async {
    final video = widget.video;
    if (_isQueued == true) {
      await WatchLaterRepository.remove(video.id);
    } else {
      await WatchLaterRepository.add(
        FavoriteVideo(
          id: video.id,
          title: video.title,
          channel: video.platform.isEmpty ? 'YouTube' : video.platform,
          thumbnailUrl: video.thumbnailUrl,
          platformUrl: video.videoUrl,
          addedAt: DateTime.now(),
        ),
      );
    }
    if (mounted) setState(() => _isQueued = _isQueued != true);
  }

  @override
  Widget build(BuildContext context) {
    final queued = _isQueued == true;
    return IconButton(
      icon: Icon(
        queued ? Icons.bookmark : Icons.bookmark_border,
        color: queued ? Colors.amber : Colors.white54,
      ),
      onPressed: _isQueued == null ? null : _toggle,
    );
  }
}

class _SleepTimerButton extends StatelessWidget {
  const _SleepTimerButton();

  static const _options = <Duration?>[
    null,
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
  ];

  String _label(Duration? d) => d == null ? 'Off' : '${d.inMinutes} min';

  void _select(BuildContext context, Duration? duration) {
    Navigator.pop(context);
    if (duration == null) {
      SleepTimerService.instance.cancel();
    } else {
      SleepTimerService.instance.start(duration, () {
        MrPlayApp.webViewKey.currentState?.controlVideo('pause');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration?>(
      valueListenable: SleepTimerService.instance.remaining,
      builder: (context, remaining, _) {
        return IconButton(
          icon: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bedtime,
                color: remaining != null ? Colors.amber : Colors.white54,
              ),
              if (remaining != null)
                Text(
                  '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.amber, fontSize: 9),
                ),
            ],
          ),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF1C1C1E),
              builder: (sheetContext) {
                return SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Sleep timer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final option in _options)
                        ListTile(
                          title: Text(
                            _label(option),
                            style: TextStyle(
                              color: (option == null && remaining == null)
                                  ? Colors.amber
                                  : Colors.white,
                            ),
                          ),
                          onTap: () => _select(sheetContext, option),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool? _isFavorite;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isFavorite = await FavoritesRepository.isFavorite(widget.video.id);
    if (mounted) setState(() => _isFavorite = isFavorite);
  }

  Future<void> _toggle() async {
    final video = widget.video;
    if (_isFavorite == true) {
      await FavoritesRepository.remove(video.id);
    } else {
      await FavoritesRepository.add(
        FavoriteVideo(
          id: video.id,
          title: video.title,
          channel: video.platform.isEmpty ? 'YouTube' : video.platform,
          thumbnailUrl: video.thumbnailUrl,
          platformUrl: video.videoUrl,
          addedAt: DateTime.now(),
        ),
      );
    }
    if (mounted) setState(() => _isFavorite = _isFavorite != true);
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = _isFavorite == true;
    return IconButton(
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: isFavorite ? Colors.red : Colors.white54,
      ),
      onPressed: _isFavorite == null ? null : _toggle,
    );
  }
}
