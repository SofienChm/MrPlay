import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../providers/player_provider.dart';
import '../models/video.dart';
import '../data/models/favorite_video.dart';
import '../data/models/queue_item.dart';
import '../data/repositories/favorites_repository.dart';
import '../data/repositories/watch_later_repository.dart';
import '../data/repositories/queue_repository.dart';
import '../services/sleep_timer_service.dart';
import '../services/native_youtube_player.dart';
import 'sleep_timer_sheet.dart';
import '../presentation/pages/queue_page.dart';
import '../presentation/widgets/error_widget.dart';
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
  bool _captionsEnabled = false;

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
        const SnackBar(
            content: Text('Added to queue'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _playNext() async {
    final video = ref.read(playerProvider).currentVideo;
    if (video == null) return;
    await QueueRepository.addNext(_queueItemOf(video));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Will play next'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _openQueue() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QueuePage()),
    );
  }

  void _togglePlayPause() {
    final notifier = ref.read(playerProvider.notifier);
    final webView = MrPlayApp.webViewKey.currentState;
    final current = ref.read(playerProvider);
    if (current.isPlaying) {
      notifier.pause();
      webView?.controlVideo('pause');
    } else {
      notifier.resume();
      webView?.controlVideo('play');
    }
  }

  void _seekBy(double seconds) {
    final current = ref.read(playerProvider);
    final target =
        current.position + Duration(milliseconds: (seconds * 1000).round());
    final clamped = target.isNegative
        ? Duration.zero
        : (current.duration > Duration.zero && target > current.duration
            ? current.duration
            : target);
    // Single seek path: seekTo fans out to the active engine.
    ref.read(playerProvider.notifier).seekTo(clamped);
  }

  void _toggleCaptions() {
    setState(() => _captionsEnabled = !_captionsEnabled);
    MrPlayApp.webViewKey.currentState?.controlVideo('toggleCaptions');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    final video = state.currentVideo;
    if (video == null || state.isMinimized) return const SizedBox.shrink();

    // Option A ("the page is the player"): for native AVPlayer playback the
    // expanded state lets the WebView watch page show through — the page's own
    // (muted) video is the visual — and floats a slim control card over it.
    if (NativeYoutubePlayer.instance.isActive) {
      return _buildNativePageMode(video);
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final progress = (_dragOffset / screenHeight).clamp(0.0, 1.0);
    final translateY = _dragOffset * (1 - progress * 0.3);
    final scale = 1 - progress * 0.05;
    final opacity = 1 - progress;

    final isSliding = _slideController.isAnimating ||
        _slideController.status == AnimationStatus.completed;

    final content = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Container(color: Colors.black),
        ),
        Positioned.fill(
          child: Builder(builder: (ctx) {
            Widget body = SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: _onVerticalDragUpdate,
                      onVerticalDragEnd: _onVerticalDragEnd,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                          Builder(builder: (ctx) {
                            final nativeActive =
                                NativeYoutubePlayer.instance.isActive;
                            final hasError = state.loadError != null;
                            Widget videoArea = ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Positioned.fill(
                                      child: nativeActive
                                          ? ValueListenableBuilder<
                                              VideoPlayerController?>(
                                              valueListenable: NativeYoutubePlayer
                                                  .instance
                                                  .videoController,
                                              builder: (ctx, controller, _) {
                                                if (controller != null) {
                                                  return Container(
                                                    color: Colors.black,
                                                    child: Center(
                                                      child: VideoPlayer(
                                                          controller),
                                                    ),
                                                  );
                                                }
                                                return _buildThumbnail(video);
                                              },
                                            )
                                          : _buildThumbnail(video),
                                    ),
                                    if (hasError)
                                      Positioned.fill(
                                        child: CustomErrorWidget(
                                          message: state.loadError!,
                                          onRetry: () => MrPlayApp.webViewKey
                                              .currentState
                                              ?.retryNativePlayback(),
                                          onSkip: () => MrPlayApp.webViewKey
                                              .currentState
                                              ?.skipNativePlayback(),
                                        ),
                                      )
                                    else
                                      Positioned.fill(
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withValues(alpha: 0.3),
                                              ),
                                            ),
                                            Center(
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  IconButton(
                                                    iconSize: 40,
                                                    icon: const Icon(
                                                        Icons.replay_10,
                                                        color: Colors.white),
                                                    tooltip:
                                                        'Back 10 seconds',
                                                    onPressed: () =>
                                                        _seekBy(-10),
                                                  ),
                                                  IconButton(
                                                    iconSize: 56,
                                                    icon: Icon(
                                                      state.isPlaying
                                                          ? Icons
                                                              .pause_circle_filled
                                                          : Icons
                                                              .play_circle_filled,
                                                      color: Colors.white,
                                                    ),
                                                    tooltip: state.isPlaying
                                                        ? 'Pause'
                                                        : 'Play',
                                                    onPressed:
                                                        _togglePlayPause,
                                                  ),
                                                  IconButton(
                                                    iconSize: 40,
                                                    icon: const Icon(
                                                        Icons.forward_10,
                                                        color: Colors.white),
                                                    tooltip:
                                                        'Forward 10 seconds',
                                                    onPressed: () =>
                                                        _seekBy(10),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  if (!nativeActive) ...[
                                                    _OverlayButton(
                                                      icon: Icons.subtitles,
                                                      active: _captionsEnabled,
                                                      tooltip: 'Captions',
                                                      onTap: _toggleCaptions,
                                                    ),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  _OverlayButton(
                                                    icon: Icons
                                                        .picture_in_picture_alt,
                                                    tooltip:
                                                        'Picture in picture',
                                                    onTap: () => MrPlayApp
                                                        .webViewKey
                                                        .currentState
                                                        ?.togglePictureInPicture(),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (!nativeActive)
                                              Positioned(
                                                bottom: 8,
                                                right: 8,
                                                child: _OverlayButton(
                                                  icon: Icons.fullscreen,
                                                  tooltip: 'Fullscreen',
                                                  onTap: () => MrPlayApp
                                                      .webViewKey.currentState
                                                      ?.controlVideo(
                                                          'fullscreen'),
                                                ),
                                              ),
                                            if (state.isBuffering)
                                              Positioned(
                                                top: 0,
                                                left: 0,
                                                right: 0,
                                                child: Center(
                                                  child: Padding(
                                                    padding: const EdgeInsets
                                                        .only(top: 16),
                                                    child: SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        valueColor:
                                                            const AlwaysStoppedAnimation<
                                                                Color>(
                                                                Colors.red),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                            if (_dragOffset > 0 && opacity < 1.0) {
                              videoArea = Opacity(
                                opacity: opacity,
                                child: videoArea,
                              );
                            }
                            return videoArea;
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Builder(builder: (ctx) {
                      Widget infoCard = Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
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
                              video.platform.isNotEmpty
                                  ? video.platform
                                  : 'YouTube',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 14),
                            ),
                            const SizedBox(height: 12),
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
                                    milliseconds:
                                        (value * state.duration.inMilliseconds)
                                            .round(),
                                  );
                                  ref.read(playerProvider.notifier).seekTo(pos);
                                },
                                onChangeEnd: (value) {
                                  final pos = Duration(
                                    milliseconds:
                                        (value * state.duration.inMilliseconds)
                                            .round(),
                                  );
                                  ref.read(playerProvider.notifier).seekTo(pos);
                                },
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(state.position),
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12),
                                  ),
                                  Text(
                                    _formatDuration(state.duration),
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.playlist_play,
                                      color: Colors.white70),
                                  tooltip: 'Play next',
                                  onPressed: _playNext,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.playlist_add,
                                      color: Colors.white70),
                                  tooltip: 'Add to queue',
                                  onPressed: _addToQueue,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.queue_music,
                                      color: Colors.white70),
                                  tooltip: 'Open queue',
                                  onPressed: _openQueue,
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                      if (_dragOffset > 0 && opacity < 1.0) {
                        infoCard = Opacity(
                          opacity: opacity,
                          child: infoCard,
                        );
                      }
                      return infoCard;
                    }),
                  ],
                ),
              ),
            );
            if (_dragOffset > 0) {
              body = Transform.translate(
                offset: Offset(0, translateY),
                child: Transform.scale(
                  scale: scale,
                  child: body,
                ),
              );
            }
            return body;
          }),
        ),
        Positioned(
          top: topPadding + 4,
          left: 16,
          child: Opacity(
            opacity: opacity,
            child: Column(
              children: [
                IconButton(
                  iconSize: 30,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.55),
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down,
                      color: Colors.white),
                  tooltip: 'Minimize',
                  onPressed: () {
                    ref.read(playerProvider.notifier).minimize();
                  },
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: topPadding + 4,
          right: 16,
          child: Opacity(
            opacity: opacity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
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
                      onPressed: () {
                        ref.read(playerProvider.notifier).dismiss();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (isSliding) {
      return SlideTransition(
        position: _slideAnimation,
        child: content,
      );
    }
    return content;
  }

  Widget _buildThumbnail(Video video) {
    return video.thumbnailUrl.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: video.thumbnailUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.grey[900]),
            errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
          )
        : Container(color: Colors.grey[900]);
  }

  /// Option A layout for native playback: the WebView watch page IS the player.
  /// Only the floating controls show — everything else is transparent and
  /// passes touches through to the page.
  Widget _buildNativePageMode(Video video) {
    final state = ref.watch(playerProvider);
    final topPadding = MediaQuery.of(context).padding.top;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Page shows through; touches fall through to the WebView.
        const IgnorePointer(child: SizedBox.expand()),
        Positioned(
          top: topPadding + 4,
          left: 12,
          child: IconButton(
            iconSize: 30,
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.55),
            ),
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            tooltip: 'Minimize',
            onPressed: () => ref.read(playerProvider.notifier).minimize(),
          ),
        ),
        Positioned(
          top: topPadding + 4,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
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
                    tooltip: 'Close',
                    onPressed: () {
                      MrPlayApp.webViewKey.currentState?.closePlayer();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // PiP source preview. The single live AVPlayerLayer lives
                      // in the always-mounted host surface (persistent_player_shell
                      // .dart) so it survives minimize; tapping this static card
                      // preview still toggles Picture in Picture.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 88,
                          height: 50,
                          child: GestureDetector(
                            onTap: () => MrPlayApp.webViewKey.currentState
                                ?.togglePictureInPicture(),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildThumbnail(video),
                                const Align(
                                  alignment: Alignment.bottomRight,
                                  child: Padding(
                                    padding: EdgeInsets.all(3),
                                    child: Icon(
                                        Icons.picture_in_picture_alt,
                                        color: Colors.white70,
                                        size: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              video.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              video.platform.isNotEmpty
                                  ? video.platform
                                  : 'YouTube',
                              maxLines: 1,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
                          milliseconds:
                              (value * state.duration.inMilliseconds).round(),
                        );
                        ref.read(playerProvider.notifier).seekTo(pos);
                      },
                      onChangeEnd: (value) {
                        final pos = Duration(
                          milliseconds:
                              (value * state.duration.inMilliseconds).round(),
                        );
                        ref.read(playerProvider.notifier).seekTo(pos);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(state.position),
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          _formatDuration(state.duration),
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 40,
                        icon: const Icon(Icons.replay_10,
                            color: Colors.white),
                        tooltip: 'Back 10 seconds',
                        onPressed: () => _seekBy(-10),
                      ),
                      IconButton(
                        iconSize: 56,
                        icon: Icon(
                          state.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: Colors.white,
                        ),
                        tooltip: state.isPlaying ? 'Pause' : 'Play',
                        onPressed: _togglePlayPause,
                      ),
                      IconButton(
                        iconSize: 40,
                        icon: const Icon(Icons.forward_10,
                            color: Colors.white),
                        tooltip: 'Forward 10 seconds',
                        onPressed: () => _seekBy(10),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _OverlayButton(
                        icon: Icons.picture_in_picture_alt,
                        tooltip: 'Picture in picture',
                        onTap: () => MrPlayApp.webViewKey.currentState
                            ?.togglePictureInPicture(),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.playlist_play,
                            color: Colors.white70),
                        tooltip: 'Play next',
                        onPressed: _playNext,
                      ),
                      IconButton(
                        icon: const Icon(Icons.playlist_add,
                            color: Colors.white70),
                        tooltip: 'Add to queue',
                        onPressed: _addToQueue,
                      ),
                      IconButton(
                        icon: const Icon(Icons.queue_music,
                            color: Colors.white70),
                        tooltip: 'Open queue',
                        onPressed: _openQueue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_WatchLaterButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      _load();
    }
  }

  Future<void> _load() async {
    final queued = await WatchLaterRepository.isQueued(widget.video.id);
    if (mounted) setState(() => _isQueued = queued);
  }

  Future<void> _toggle() async {
    if (_busy || _isQueued == null) return;
    _busy = true;
    final target = _isQueued != true;
    try {
      final video = widget.video;
      if (target) {
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
      } else {
        await WatchLaterRepository.remove(video.id);
      }
      if (mounted) setState(() => _isQueued = target);
    } finally {
      _busy = false;
    }
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
          onPressed: () => showSleepTimerSheet(context),
        );
      },
    );
  }
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool? _isFavorite;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      _load();
    }
  }

  Future<void> _load() async {
    final isFavorite = await FavoritesRepository.isFavorite(widget.video.id);
    if (mounted) setState(() => _isFavorite = isFavorite);
  }

  Future<void> _toggle() async {
    if (_busy || _isFavorite == null) return;
    _busy = true;
    final target = _isFavorite != true;
    try {
      final video = widget.video;
      if (target) {
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
      } else {
        await FavoritesRepository.remove(video.id);
      }
      if (mounted) setState(() => _isFavorite = target);
    } finally {
      _busy = false;
    }
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

class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  const _OverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: active
                ? Colors.red.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
