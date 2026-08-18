import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    show VideoId;

import '../models/video.dart';
import 'playback_stats_service.dart';
import 'youtube_stream_resolver.dart';

/// Plays YouTube videos through a native AVPlayer (via [VideoPlayerController])
/// instead of the WebView.
///
/// Owns the active controller and feeds playback state to the owner through the
/// same map shapes the WebView JS handlers use, so [PersistentWebViewState]
/// reuses its existing sync / now-playing / ended-handling logic unchanged.
class NativeYoutubePlayer {
  NativeYoutubePlayer._();

  static final NativeYoutubePlayer instance = NativeYoutubePlayer._();

  /// Whether [url] is a YouTube video (watch/shorts/embed/live) that should be
  /// played natively. Non-video YouTube pages keep using the WebView.
  static bool isYouTubeVideoUrl(String url) => VideoId.parseVideoId(url) != null;

  final YoutubeStreamResolver _resolver = YoutubeStreamResolver();

  /// The active native controller. Watch for non-null to render the surface.
  final ValueNotifier<VideoPlayerController?> videoController =
      ValueNotifier<VideoPlayerController?>(null);

  VideoPlayerController? _controller;
  String? _activeVideoId;
  String? _activeUrl;
  String _activeTitle = 'YouTube video';
  String _activeThumbnail = '';
  int _loadToken = 0;
  bool _inFlight = false;
  bool _retriedOnce = false;
  bool _wasCompleted = false;
  bool _failed = false;

  /// Same shape as the WebView `videoState` JS handler (position/duration in
  /// seconds), plus a `buffering` flag.
  void Function(Map<String, dynamic> data)? onVideoState;

  /// Same shape as the WebView `playerInfo` JS handler.
  void Function(Map<String, dynamic> data)? onPlayerInfo;

  /// Called when the stream cannot be resolved or playback fails permanently.
  void Function(YoutubeStreamException error)? onLoadFailed;

  bool get isActive => _controller != null || _inFlight || _failed;

  /// The URL currently loaded for native playback (null when inactive). Used
  /// to dedupe repeated SPA navigations to the same video.
  String? get activeUrl => _activeUrl;

  /// Resolves [url] (a YouTube watch/shorts/embed/live URL) and starts native
  /// playback. Streams are resolved fresh on every call because direct URLs
  /// expire.
  Future<void> load(String url, {Video? video}) async {
    final videoId = VideoId.parseVideoId(url);
    if (videoId == null) return;

    _activeVideoId = videoId;
    _activeUrl = url;
    _activeTitle = (video?.title.isNotEmpty ?? false)
        ? video!.title
        : 'YouTube video';
    _activeThumbnail = video?.thumbnailUrl ??
        'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    _retriedOnce = false;

    await _startPlayback(videoId, url, _loadToken + 1);
  }

  /// Re-resolves the current video (used by the error widget retry button).
  Future<void> retry() async {
    final id = _activeVideoId;
    final url = _activeUrl;
    if (id == null || url == null) return;
    _retriedOnce = false;
    await _startPlayback(id, url, _loadToken + 1);
  }

  /// Tears down native playback and clears the surface.
  Future<void> close() async {
    _activeVideoId = null;
    _activeUrl = null;
    _failed = false;
    _retriedOnce = false;
    _wasCompleted = false;
    _loadToken++;
    await _stopPlayback();
  }

  Future<void> play() async {
    try {
      await _controller?.play();
    } catch (_) {}
  }

  Future<void> pause() async {
    try {
      await _controller?.pause();
    } catch (_) {}
  }

  Future<void> seekTo(Duration position) async {
    try {
      await _controller?.seekTo(position);
    } catch (_) {}
  }

  Future<void> _startPlayback(
    String videoId,
    String url,
    int token,
  ) async {
    _loadToken = token;
    _inFlight = true;
    _failed = false;
    await _stopPlayback();
    if (token != _loadToken) return;

    try {
      final resolution = await _resolver.resolve(videoId);
      if (token != _loadToken) return;

      String title = _activeTitle;
      String channel = 'YouTube';
      String thumbnail = _activeThumbnail;
      try {
        final info = await _resolver.fetchInfo(videoId);
        if (info != null) {
          if (info.title.isNotEmpty) title = info.title;
          if (info.channel.isNotEmpty) channel = info.channel;
          if (info.thumbnailUrl.isNotEmpty) thumbnail = info.thumbnailUrl;
        }
      } catch (_) {}
      if (token != _loadToken) return;
      _activeTitle = title;

      final controller = VideoPlayerController.networkUrl(
        resolution.url,
        videoPlayerOptions:
            VideoPlayerOptions(allowBackgroundPlayback: true),
        viewType: defaultTargetPlatform == TargetPlatform.iOS
            ? VideoViewType.platformView
            : VideoViewType.textureView,
      );
      _controller = controller;
      videoController.value = controller;
      controller.addListener(_handleValueChanged);

      try {
        await controller.initialize();
      } catch (_) {
        if (token != _loadToken) return;
        _retryExpiredOrFail('Playback could not start.');
        return;
      }
      if (token != _loadToken) return;

      await controller.setLooping(false);
      _wasCompleted = false;

      onPlayerInfo?.call({
        'id': videoId,
        'title': title,
        'channel': channel,
        'thumbnailUrl': thumbnail,
        'videoUrl': url,
        'platform': 'YouTube',
      });

      if (!resolution.isHls) {
        final resumeMs =
            await PlaybackStatsService.instance.resumePosition(videoId);
        if (resumeMs > 0 && token == _loadToken) {
          await controller.seekTo(Duration(seconds: resumeMs));
        }
      }
      if (token != _loadToken) return;
      await controller.play();
      _emitState(playing: true);
    } on YoutubeStreamException catch (e) {
      if (token == _loadToken) {
        _failed = true;
        onLoadFailed?.call(e);
      }
    } catch (e) {
      if (token == _loadToken) {
        _failed = true;
        onLoadFailed?.call(YoutubeStreamException(
          YoutubeStreamErrorType.unknown,
          'Playback could not start.',
          cause: e,
        ));
      }
    } finally {
      if (token == _loadToken) _inFlight = false;
    }
  }

  /// A single retry with a freshly resolved manifest, then permanent failure.
  void _retryExpiredOrFail(String message) {
    if (_retriedOnce) {
      _failed = true;
      onLoadFailed?.call(YoutubeStreamException(
        YoutubeStreamErrorType.unknown,
        message,
      ));
      return;
    }
    _retriedOnce = true;
    final id = _activeVideoId;
    final url = _activeUrl;
    if (id == null || url == null) return;
    _startPlayback(id, url, _loadToken + 1);
  }

  void _handleValueChanged() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (!value.isInitialized) return;

    if (value.hasError) {
      _retryExpiredOrFail(
        value.errorDescription ?? 'Playback failed while playing.',
      );
      return;
    }

    final completed = value.isCompleted;
    final ended = completed && !_wasCompleted;
    _wasCompleted = completed;

    _emitState(
      playing: value.isPlaying,
      ended: ended,
      buffering: value.isBuffering,
      position: value.position,
      duration: value.duration,
    );
  }

  void _emitState({
    required bool playing,
    bool ended = false,
    bool? buffering,
    Duration? position,
    Duration? duration,
  }) {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    onVideoState?.call({
      'playing': playing,
      'position': (position ?? value.position).inMilliseconds / 1000.0,
      'duration': (duration ?? value.duration).inMilliseconds / 1000.0,
      'ended': ended,
      'buffering': buffering ?? value.isBuffering,
    });
  }

  Future<void> _stopPlayback() async {
    _inFlight = false;
    final controller = _controller;
    _controller = null;
    if (videoController.value == controller) {
      videoController.value = null;
    }
    if (controller != null) {
      controller.removeListener(_handleValueChanged);
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }
}
