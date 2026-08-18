import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:audio_session/audio_session.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/youtube_js.dart';
import '../../core/constants/content_blocker_js.dart';
import '../../core/constants/media_observer_js.dart';
import '../../models/video.dart';
import '../../providers/player_provider.dart';
import '../../services/media_controls_service.dart';
import '../../services/playback_stats_service.dart';
import '../../services/data_export_service.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/watch_later_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/models/favorite_video.dart';
import '../../presentation/pages/settings_page.dart';
import '../../presentation/pages/favorites_page.dart';
import '../../widgets/sleep_timer_sheet.dart';
import 'error_widget.dart';

class PersistentWebView extends ConsumerStatefulWidget {
  const PersistentWebView({super.key});

  @override
  ConsumerState<PersistentWebView> createState() => PersistentWebViewState();
}

class PersistentWebViewState extends ConsumerState<PersistentWebView>
    with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  bool isReady = false;
  bool _isLoading = false;
  String? _pendingUrl;
  String? _currentUrl;
  String? _loadError;
  Timer? _loadingTimer;
  Timer? _nowPlayingThrottle;
  bool _endedHandled = false;
  bool _resumeSeekDone = false;
  bool _appIsBackgrounded = false;
  int _lastNowPlayingMs = 0;
  Timer? _statePoll;

  /// JS that resolves the actively-playing `<video>` (falling back to the
  /// first one), so controls target the real playback element rather than a
  /// stale/ad/preview video that `document.querySelector('video')` may hit.
  static const String _activeVideoJs = '''
    (function() {
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        if (!videos[i].paused && !videos[i].ended) return videos[i];
      }
      return videos.length > 0 ? videos[0] : null;
    })()
  ''';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MediaControlsService.instance.setRemoteCommandHandler(_onRemoteCommand);
    _restoreLastPlatform();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadingTimer?.cancel();
    _nowPlayingThrottle?.cancel();
    _statePoll?.cancel();
    PlaybackStatsService.instance.flush();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _appIsBackgrounded = true;
    } else if (state == AppLifecycleState.paused) {
      _enterBackground();
    } else if (state == AppLifecycleState.resumed) {
      _appIsBackgrounded = false;
      // The video was phantom-PiP'd on background to keep audio alive. Restore
      // it inline after a short delay so WebKit can finish its own reattachment
      // first; the restore is event-driven (webkitpresentationmodechanged)
      // with a page reload as a last resort.
      Future.delayed(const Duration(milliseconds: 300), _restoreVideoInline);
    }
  }

  void _enterBackground() {
    _appIsBackgrounded = true;
    _reassertAudioSession();
    if (ref.read(playerProvider).isPlaying) {
      _enterPhantomPiP();
    }
  }

  Future<void> _reassertAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
    controller.addJavaScriptHandler(
      handlerName: 'playerInfo',
      callback: (args) {
        if (args.isNotEmpty && args.first is Map) {
          _onPlayerInfo(args.first as Map<String, dynamic>);
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'videoState',
      callback: (args) {
        if (args.isNotEmpty && args.first is Map) {
          _onVideoState(args.first as Map<String, dynamic>);
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'playerControl',
      callback: (args) {
        if (args.isEmpty || args.first is! Map) return;
        final action =
            (args.first as Map<String, dynamic>)['action'] as String?;
        switch (action) {
          case 'toggleCaptions':
            controlVideo('toggleCaptions');
            break;
          case 'pip':
            togglePictureInPicture();
            break;
          case 'fullscreen':
            controlVideo('fullscreen');
            break;
        }
      },
    );
    if (_pendingUrl != null) {
      controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(_pendingUrl!)),
      );
      _pendingUrl = null;
    }
  }

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    _currentUrl = url?.toString();
    if (mounted) setState(() => _isLoading = true);
    if (_loadError != null && mounted) setState(() => _loadError = null);
    _loadingTimer?.cancel();
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _onLoadStop(
      InAppWebViewController controller, WebUri? url) async {
    _loadingTimer?.cancel();
    if (mounted) setState(() => _isLoading = false);
    _handleWatchPage(controller, url.toString());
  }

  /// YouTube mobile is a single-page app: tapping a video navigates to /watch
  /// via the history API, so neither onLoadStart nor onLoadStop fires. iOS
  /// reports those URL changes through onUpdateVisitedHistory (KVO on
  /// WKWebView.url) - without this the current URL stays stale and the mini
  /// player never appears for SPA-opened videos.
  void _onUpdateVisitedHistory(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  ) {
    final urlStr = url?.toString();
    if (urlStr == null) return;
    _currentUrl = urlStr;
    _handleWatchPage(controller, urlStr);
  }

  /// Runs the watch-page tasks (title extraction for the mini player and
  /// resume-seek). Safe to call repeatedly for the same page: playerInfo is
  /// deduped by video id and the seek is guarded by [_resumeSeekDone].
  void _handleWatchPage(InAppWebViewController controller, String urlStr) {
    if (urlStr.contains('youtube.com')) {
      if (urlStr.contains('/watch')) {
        Future.delayed(const Duration(milliseconds: 1500), () async {
          if (!mounted) return;
          await controller.evaluateJavascript(source: '''
            (function() {
              var titleEl = document.querySelector('h1.title, .slim-video-information-title, .ytp-title, #title h1');
              var videoId = window.location.search.match(/[?&]v=([^&]+)/);
              var title = titleEl ? titleEl.textContent.trim().substring(0, 200) : '';
              if (title && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('playerInfo', {
                  id: videoId ? videoId[1] : '',
                  title: title,
                  thumbnailUrl: videoId ? 'https://i.ytimg.com/vi/' + videoId[1] + '/hqdefault.jpg' : '',
                  videoUrl: window.location.href,
                  platform: 'YouTube'
                });
              }
            })();
          ''');
        });

        // Resume where you left off: if we have stored progress for this video,
        // seek once the player is actually ready (skip for live streams).
        final videoIdMatch = RegExp(r'[?&]v=([^&]+)').firstMatch(urlStr);
        final videoId = videoIdMatch?.group(1) ?? '';
        if (videoId.isNotEmpty) {
          PlaybackStatsService.instance
              .resumePosition(videoId)
              .then((resumeMs) {
            if (resumeMs > 0) {
              Future.delayed(const Duration(milliseconds: 3500), () async {
                if (!mounted) return;
                if (_resumeSeekDone) return;
                _resumeSeekDone = true;
                await controller.evaluateJavascript(source: '''
                  (function() {
                    var v = document.querySelector('video');
                    if (v && v.duration > 10 && isFinite(v.duration)) {
                      v.currentTime = $resumeMs;
                    }
                  })();
                ''');
              });
            }
          });
        }
      }
    }
  }

  void _onPlayerInfo(Map<String, dynamic> data) {
    try {
      final title = data['title'] as String? ?? '';
      if (title.isNotEmpty) {
        final video = Video(
          id: data['id'] ?? '',
          title: title,
          thumbnailUrl: data['thumbnailUrl'] ?? '',
          videoUrl: data['videoUrl'] ?? '',
          platform: data['platform'] ?? 'YouTube',
        );
        final currentId = ref.read(playerProvider).currentVideo?.id;
        if (currentId != video.id) {
          _endedHandled = false;
          _resumeSeekDone = false;
          ref.read(playerProvider.notifier).play(video);
          MediaControlsService.instance.updateNowPlaying(
            title: video.title,
            artist: video.platform.isEmpty ? 'YouTube' : video.platform,
            position: Duration.zero,
            duration: Duration.zero,
            isPlaying: true,
            artworkUrl: video.thumbnailUrl,
          );
          _lastNowPlayingMs = 0;
        } else {
          // Same video already tracked (fallback placeholder created it):
          // upgrade its metadata to the real title/thumbnail.
          final current = ref.read(playerProvider).currentVideo;
          if (current != null &&
              (current.title == 'YouTube video' ||
                  current.title == 'Playing video')) {
            ref.read(playerProvider.notifier).updateMetadata(video);
          }
        }
      }
    } catch (_) {}
  }

  void _onVideoState(Map<String, dynamic> data) {
    try {
      final playing = data['playing'] == true;
      final ended = data['ended'] == true;
      // Live streams can report non-finite position/duration - clamp to 0 so
      // Duration(milliseconds:) never receives Infinity/NaN (which throws).
      final posSec = (data['position'] as num?)?.toDouble() ?? 0;
      final durSec = (data['duration'] as num?)?.toDouble() ?? 0;
      final positionMs = posSec.isFinite ? posSec * 1000 : 0.0;
      final durationMs = durSec.isFinite ? durSec * 1000 : 0.0;
      var video = ref.read(playerProvider).currentVideo;
      // Fallback: if the video is actually playing but the `playerInfo` JS
      // (title extraction) never reported in, build the Video from the current
      // URL so the mini player / stats / media controls still appear.
      if (video == null && playing && !ended) {
        video = _trackVideoFromUrl();
      }
      if (video != null) {
        ref.read(playerProvider.notifier).syncState(
              isPlaying: playing,
              position: Duration(milliseconds: positionMs.round()),
              duration: Duration(milliseconds: durationMs.round()),
              ended: ended,
            );
        _updateNowPlayingThrottled(
          positionMs: positionMs.round(),
          durationMs: durationMs.round(),
          playing: playing,
        );
        if (playing && !ended) {
          PlaybackStatsService.instance.saveProgress(
            video.id,
            Duration(milliseconds: positionMs.round()),
          );
        }
      }
      if (!playing && !_appIsBackgrounded && ended) {
        PlaybackStatsService.instance.flush();
        final id = video?.id ?? '';
        if (id.isNotEmpty) PlaybackStatsService.instance.clearProgress(id);
        _handleEnded();
      }
    } catch (_) {}
  }

  /// Builds and tracks a [Video] from the current watch URL when the
  /// `playerInfo` JS title extraction never reported in, so the mini player /
  /// stats / media controls still appear. Returns the tracked video (or the
  /// already-tracked one, or null when the URL has no video id).
  Video? _trackVideoFromUrl() {
    final existing = ref.read(playerProvider).currentVideo;
    if (existing != null) return existing;
    final url = _currentUrl ?? '';
    final idMatch = RegExp(r'[?&]v=([^&]+)').firstMatch(url);
    final String videoId;
    final String thumbnailUrl;
    final String platform;
    if (idMatch != null) {
      videoId = idMatch.group(1)!;
      thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      platform = 'YouTube';
    } else {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty) return null;
      videoId = url;
      thumbnailUrl = '';
      platform = _platformNameFromUrl(uri.host);
    }
    final video = Video(
      id: videoId,
      title: 'Playing video',
      thumbnailUrl: thumbnailUrl,
      videoUrl: url,
      platform: platform,
    );
    ref.read(playerProvider.notifier).play(video);
    return video;
  }

  String _platformNameFromUrl(String host) {
    var h = host;
    if (h.startsWith('m.')) {
      h = h.substring(2);
    } else if (h.startsWith('www.')) {
      h = h.substring(4);
    }
    final first = h.split('.').first;
    if (first.isEmpty) return 'Web';
    return '${first[0].toUpperCase()}${first.substring(1)}';
  }

  void _updateNowPlayingThrottled({
    required int positionMs,
    required int durationMs,
    required bool playing,
  }) {
    if (positionMs - _lastNowPlayingMs < 1000) return;
    _lastNowPlayingMs = positionMs;
    MediaControlsService.instance.updateProgress(
      position: Duration(milliseconds: positionMs),
      duration: Duration(milliseconds: durationMs),
      isPlaying: playing,
    );
  }

  Future<void> _handleEnded() async {
    if (_endedHandled) return;
    _endedHandled = true;
    final items = await QueueRepository.getAll();
    if (items.isEmpty) return;
    final next = items.first;
    await QueueRepository.remove(next.id);
    exitPiP();
    if (mounted) loadUrl(next.platformUrl);
  }

  void _onRemoteCommand(String command, {Duration? position}) {
    final state = ref.read(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final positionMs = position?.inMilliseconds ?? 0;
    switch (command) {
      case 'play':
        notifier.resume();
        controlVideo('play');
        break;
      case 'pause':
        userInitiatedPause();
        break;
      case 'toggle':
        if (state.isPlaying) {
          userInitiatedPause();
        } else {
          notifier.resume();
          controlVideo('play');
        }
        break;
      case 'skipForward':
        final next = state.position + const Duration(seconds: 15);
        notifier.seekTo(next);
        controlVideo('seek', position: next.inMilliseconds / 1000.0);
        break;
      case 'skipBackward':
        final prev = state.position - const Duration(seconds: 15);
        final clamped = prev.isNegative ? Duration.zero : prev;
        notifier.seekTo(clamped);
        controlVideo('seek', position: clamped.inMilliseconds / 1000.0);
        break;
      case 'seek':
        if (positionMs > 0) {
          final target = Duration(milliseconds: positionMs);
          notifier.seekTo(target);
          controlVideo('seek', position: target.inMilliseconds / 1000.0);
        }
        break;
    }
  }

  /// Pauses playback as an explicit user action (lock screen / Control Center
  /// / sleep timer).
  void userInitiatedPause() {
    ref.read(playerProvider.notifier).pause();
    controlVideo('pause');
  }

  /// Shows the mini player: tracks the currently-playing video if needed (so
  /// there is something to display) and collapses the full player. Bound to
  /// the mini-player overlay button in the webview.
  void showMiniPlayer() {
    _trackVideoFromUrl();
    if (ref.read(playerProvider).currentVideo != null) {
      ref.read(playerProvider.notifier).minimize();
    }
  }

  void _showOptionsModal() {
    final video = ref.read(playerProvider).currentVideo;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.85;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SheetMenuItem(
                      icon: Icons.picture_in_picture_alt,
                      label: 'Picture in Picture',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        togglePictureInPicture();
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.bookmark_border,
                      label: 'Add to Bookmarks',
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        if (video == null) return;
                        final already =
                            await WatchLaterRepository.isQueued(video.id);
                        if (already) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Already in bookmarks'),
                                  duration: Duration(seconds: 1)),
                            );
                          }
                          return;
                        }
                        await WatchLaterRepository.add(FavoriteVideo(
                          id: video.id,
                          title: video.title,
                          channel: video.platform.isEmpty
                              ? 'YouTube'
                              : video.platform,
                          thumbnailUrl: video.thumbnailUrl,
                          platformUrl: video.videoUrl,
                          addedAt: DateTime.now(),
                        ));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Added to bookmarks'),
                                duration: Duration(seconds: 1)),
                          );
                        }
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.bookmarks,
                      label: 'View Bookmarks',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const FavoritesPage()),
                        );
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.bedtime,
                      label: 'Sleep Timer',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Future.delayed(const Duration(milliseconds: 400), () {
                          if (mounted) showSleepTimerSheet(context);
                        });
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.airplay,
                      label: 'AirPlay',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _webViewController?.evaluateJavascript(source: '''
                        (function(){
                          var v=document.querySelector('video');
                          if(v&&v.webkitShowPlaybackTargetPicker)
                            v.webkitShowPlaybackTargetPicker();
                        })();
                      ''');
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.share,
                      label: 'Share Link',
                      onTap: () {
                        var shareUrl = video?.videoUrl ?? '';
                        if (shareUrl.isEmpty &&
                            video != null &&
                            video.id.isNotEmpty) {
                          shareUrl =
                              'https://www.youtube.com/watch?v=${video.id}';
                        }
                        if (shareUrl.isEmpty) shareUrl = _currentUrl ?? '';
                        final shareTitle = video?.title ?? 'MrPlay Video';
                        // iPad presents the share sheet as a popover and requires
                        // a source rect, otherwise it silently drops the sheet.
                        final origin = _sharePositionOrigin();
                        Navigator.pop(sheetContext);
                        // Defer Share.share until the bottom sheet's dismiss
                        // animation completes. iOS silently drops a share sheet
                        // presented on a controller mid-dismiss, which is why the
                        // button appeared to do nothing.
                        if (shareUrl.isNotEmpty) {
                          Future.delayed(const Duration(milliseconds: 400), () {
                            Share.share(
                              shareUrl,
                              subject: shareTitle,
                              sharePositionOrigin: origin,
                            );
                          });
                        }
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.settings,
                      label: 'Settings',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SettingsPage()),
                        );
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.file_upload_outlined,
                      label: 'Export Data',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        DataExportService.instance.exportToJson();
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1, indent: 56),
                    _SheetMenuItem(
                      icon: Icons.file_download_outlined,
                      label: 'Import Data',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Share a .json or .csv file to MrPlay to import'),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Returns a screen-anchored rect used as the popover source on iPad, where
  /// [Share.share] requires a non-null `sharePositionOrigin` or it drops the
  /// sheet silently.
  Rect _sharePositionOrigin() {
    final size = MediaQuery.of(context).size;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 1,
      height: 1,
    );
  }

  /// Full cleanup: pauses the video, cancels timers, stops audio keep-alive,
  /// clears now-playing, flushes stats, and dismisses the player state.
  void closePlayer() {
    controlVideo('pause');
    _stopStatePoll();
    _loadingTimer?.cancel();
    _loadingTimer = null;
    _nowPlayingThrottle?.cancel();
    _nowPlayingThrottle = null;
    PlaybackStatsService.instance.flush();
    MediaControlsService.instance.clearNowPlaying();
    ref.read(playerProvider.notifier).dismiss();
  }

  void controlVideo(String action, {double? position}) {
    final controller = _webViewController;
    if (controller == null) return;
    switch (action) {
      case 'play':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = $_activeVideoJs;
            if (v) v.play().catch(function(){});
          })();
        ''');
        break;
      case 'pause':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = $_activeVideoJs;
            if (v) v.pause();
          })();
        ''');
        break;
      case 'seek':
        if (position != null) {
          controller.evaluateJavascript(source: '''
            (function() {
              var v = $_activeVideoJs;
              if (v) v.currentTime = $position;
            })();
          ''');
        }
        break;
      case 'toggleCaptions':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = $_activeVideoJs;
            if (!v || !v.textTracks || v.textTracks.length === 0) return;
            var anyShown = false;
            for (var i = 0; i < v.textTracks.length; i++) {
              if (v.textTracks[i].mode === 'showing') { anyShown = true; break; }
            }
            for (var j = 0; j < v.textTracks.length; j++) {
              v.textTracks[j].mode = anyShown ? 'hidden' : 'showing';
            }
          })();
        ''');
        break;
      case 'fullscreen':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = $_activeVideoJs;
            if (!v) return;
            if (v.requestFullscreen) {
              if (document.fullscreenElement) {
                document.exitFullscreen().catch(function(){});
              } else {
                v.requestFullscreen().catch(function(){});
              }
            } else if (v.webkitEnterFullscreen) {
              v.webkitEnterFullscreen();
            }
          })();
        ''');
        break;
    }
  }

  Future<void> _restoreLastPlatform() async {
    final url = await SettingsRepository.getLastPlatformUrl();
    if (url == null || url.isEmpty || !mounted) return;
    loadUrl(url);
  }

  void loadUrl(String url) {
    _loadingTimer?.cancel();
    _pendingUrl = url;
    if (_webViewController != null) {
      _webViewController!.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
    }
    setState(() {
      isReady = true;
      _isLoading = true;
    });
    _endedHandled = false;
    _resumeSeekDone = false;
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (request.isForMainFrame != false) {
      if (mounted) {
        setState(
            () => _loadError = 'Could not load the page: ${error.description}');
      }
    }
  }

  void _onReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse response,
  ) {
    if (request.isForMainFrame != false) {
      if (mounted) {
        setState(() {
          _loadError = 'Server error ${response.statusCode ?? 'unknown'}';
        });
      }
    }
  }

  void _retryLoad() {
    if (!mounted) return;
    setState(() => _loadError = null);
    _webViewController?.reload();
  }

  /// Enters native Picture-in-Picture for the actively-playing video. Only
  /// called from explicit user actions (PiP button / swipe-down), so iOS
  /// presents the real floating window.
  void enterPiP() {
    _webViewController?.evaluateJavascript(source: '''
      (function() {
        var video = $_activeVideoJs;
        if (!video) return;
        if (video.requestPictureInPicture) {
          video.requestPictureInPicture().catch(function(){});
        } else if (video.webkitSetPresentationMode) {
          if (video.webkitPresentationMode !== 'picture-in-picture') {
            video.webkitSetPresentationMode('picture-in-picture');
          }
        }
      })();
    ''');
  }

  /// Brings the video back inline after PiP. Uses only the clean API call —
  /// no DOM surgery, so it can't corrupt YouTube's MediaSource pipeline.
  void exitPiP() {
    _webViewController?.evaluateJavascript(source: '''
      (function() {
        var video = $_activeVideoJs;
        if (!video) return;
        if (document.exitPictureInPicture && document.pictureInPictureElement) {
          document.exitPictureInPicture().catch(function(){});
        } else if (video.webkitSetPresentationMode &&
                   video.webkitPresentationMode === 'picture-in-picture') {
          video.webkitSetPresentationMode('inline');
        }
      })();
    ''');
  }

  void togglePictureInPicture() {
    _webViewController?.evaluateJavascript(source: '''
      (function() {
        var video = $_activeVideoJs;
        if (!video) return;
        if (video.requestPictureInPicture) {
          if (document.pictureInPictureElement) {
            document.exitPictureInPicture().catch(function(){});
          } else {
            video.requestPictureInPicture().catch(function(){});
          }
        } else if (video.webkitSetPresentationMode) {
          video.webkitSetPresentationMode(
            video.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture'
          );
        }
      })();
    ''');
  }

  /// Restores the video inline after phantom PiP (used on background to keep
  /// audio alive). Event-driven: waits for webkitpresentationmodechanged to
  /// confirm 'inline', verifies rendering, and reloads the page as a last
  /// resort — no DOM surgery, which corrupts YouTube's MediaSource pipeline.
  Future<void> _restoreVideoInline() async {
    final controller = _webViewController;
    if (controller == null) return;
    try {
      final result = await controller.callAsyncJavaScript(functionBody: '''
        var videos = document.querySelectorAll('video');
        var video = null;
        for (var i = 0; i < videos.length; i++) {
          if (!videos[i].paused && !videos[i].ended) { video = videos[i]; break; }
        }
        if (!video && videos.length > 0) video = videos[0];
        if (!video) return { ok: true, reason: 'no-video' };
        if (!video.webkitSetPresentationMode ||
            video.webkitPresentationMode !== 'picture-in-picture') {
          return { ok: true, reason: 'already-inline' };
        }
        return new Promise(function(resolve) {
          var done = false;
          var timer = setTimeout(function() {
            if (done) return;
            done = true;
            video.removeEventListener('webkitpresentationmodechanged', onMode);
            resolve({ ok: false, reason: 'timeout' });
          }, 1500);
          function onMode() {
            if (video.webkitPresentationMode !== 'inline') return;
            if (done) return;
            done = true;
            clearTimeout(timer);
            video.removeEventListener('webkitpresentationmodechanged', onMode);
            var rendered = video.videoWidth > 0;
            resolve({ ok: rendered, reason: rendered ? 'inline' : 'no-render' });
          }
          video.addEventListener('webkitpresentationmodechanged', onMode);
          try {
            video.webkitSetPresentationMode('inline');
          } catch (e) {
            if (done) return;
            done = true;
            clearTimeout(timer);
            video.removeEventListener('webkitpresentationmodechanged', onMode);
            resolve({ ok: false, reason: 'api-error' });
          }
        });
      ''');
      final value = result?.value;
      final ok = value is Map && value['ok'] == true;
      if (!ok) {
        _webViewController?.reload();
      }
    } catch (_) {
      _webViewController?.reload();
    }
  }

  /// Enters phantom PiP on background and makes sure the video is actually
  /// playing inside the PiP session. iOS pauses the webview video when the app
  /// backgrounds; the PiP handoff alone leaves it paused (no audio). We wait for
  /// the mode-change event, then resume playback so the PiP/AVFoundation session
  /// keeps the audio alive.
  Future<void> _enterPhantomPiP() async {
    final controller = _webViewController;
    if (controller == null) return;
    try {
      final result = await controller.callAsyncJavaScript(functionBody: '''
        var videos = document.querySelectorAll('video');
        var video = null;
        for (var i = 0; i < videos.length; i++) {
          if (!videos[i].paused && !videos[i].ended) { video = videos[i]; break; }
        }
        if (!video && videos.length > 0) video = videos[0];
        if (!video || !video.webkitSetPresentationMode) return { ok: false, reason: 'no-video' };
        try { video.disablePictureInPicture = false; video.removeAttribute('disablepictureinpicture'); } catch (e) {}
        if (video.webkitPresentationMode !== 'picture-in-picture') {
          await new Promise(function(resolve) {
            var timer = setTimeout(function() {
              cleanup();
              resolve();
            }, 1500);
            function onMode() {
              if (video.webkitPresentationMode === 'picture-in-picture') {
                cleanup();
                resolve();
              }
            }
            function cleanup() {
              clearTimeout(timer);
              video.removeEventListener('webkitpresentationmodechanged', onMode);
            }
            video.addEventListener('webkitpresentationmodechanged', onMode);
            try {
              video.webkitSetPresentationMode('picture-in-picture');
            } catch (e) {
              cleanup();
              resolve();
            }
          });
        }
        if (video.paused) {
          for (var attempt = 0; attempt < 2; attempt++) {
            try {
              await video.play();
              break;
            } catch (e) {
              if (attempt === 1) return { ok: false, reason: 'play-rejected' };
              await new Promise(function(r) { setTimeout(r, 200); });
            }
          }
        }
        return { ok: !video.paused, reason: video.paused ? 'still-paused' : 'playing' };
      ''');
      final value = result?.value;
      if (value is Map && value['ok'] != true) {
        debugPrint('[MrPlay] phantom PiP failed: ${value['reason']}');
      }
    } catch (_) {
      // WebContent may already be suspended; nothing else we can do from Dart.
    }
  }

  /// Polls the webview for the live video position/duration from the Dart side.
  /// While the full player overlays the webview, iOS can throttle the page's
  /// own timers/events, so the JS `reportState` heartbeat may stop firing and
  /// the seek slider / timer freeze. This keeps `position`/`duration` fresh
  /// regardless of page-side throttling.
  void _startStatePoll() {
    _statePoll?.cancel();
    _statePoll = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollVideoState(),
    );
  }

  void _stopStatePoll() {
    _statePoll?.cancel();
    _statePoll = null;
  }

  Future<void> _pollVideoState() async {
    final controller = _webViewController;
    if (controller == null) return;
    try {
      final result = await controller.evaluateJavascript(source: '''
        (function() {
          var videos = document.querySelectorAll('video');
          var v = null;
          for (var i = 0; i < videos.length; i++) {
            if (!videos[i].paused && !videos[i].ended) { v = videos[i]; break; }
          }
          if (!v && videos.length > 0) v = videos[0];
          if (!v) return null;
          var pipStuck = false;
          var pipActive = false;
          try {
            pipStuck = (typeof v.webkitPresentationMode !== 'undefined') &&
                       v.webkitPresentationMode === 'picture-in-picture';
            pipActive = (typeof document.pictureInPictureElement !== 'undefined' &&
                         !!document.pictureInPictureElement);
          } catch (e) {}
          return {
            playing: !v.paused && !v.ended,
            position: isFinite(v.currentTime) ? v.currentTime : 0,
            duration: isFinite(v.duration) ? v.duration : 0,
            ended: !!v.ended,
            pip: pipStuck || pipActive,
            pipActive: pipActive,
            pipStuck: pipStuck && !pipActive
          };
        })();
      ''');
      if (result is Map) {
        _onVideoState(Map<String, dynamic>.from(result));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playerProvider, (prev, next) {
      final videoAppeared =
          prev?.currentVideo == null && next.currentVideo != null;
      final videoGone = prev?.currentVideo != null && next.currentVideo == null;
      if (videoAppeared) _startStatePoll();
      if (videoGone) _stopStatePoll();
    });
    if (!isReady) return const SizedBox.shrink();

    return Stack(
      children: [
        Positioned.fill(
          child: InAppWebView(
            initialUserScripts: UnmodifiableListView([
              UserScript(
                source: ContentBlockerJS.genericAdBlockerScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
              UserScript(
                source: YouTubeJS.visibilityKeepAliveScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
              UserScript(
                source: YouTubeJS.appBannerRemoverScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
              UserScript(
                source: YouTubeJS.playerControlsScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
              UserScript(
                source: MediaObserverJS.genericObserverScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              allowBackgroundAudioPlaying: true,
              allowsPictureInPictureMediaPlayback: true,
              allowsAirPlayForMediaPlayback: true,
              isFraudulentWebsiteWarningEnabled: false,
              userAgent:
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
            ),
            onWebViewCreated: _onWebViewCreated,
            onLoadStart: _onLoadStart,
            onLoadStop: _onLoadStop,
            onUpdateVisitedHistory: _onUpdateVisitedHistory,
            onReceivedError: _onReceivedError,
            onReceivedHttpError: _onReceivedHttpError,
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url;
              if (url != null) {
                final scheme = url.scheme.toLowerCase();
                if (scheme == 'http' ||
                    scheme == 'https' ||
                    scheme == 'about' ||
                    scheme == 'file') {
                  return NavigationActionPolicy.ALLOW;
                }
                if (scheme == 'javascript' ||
                    scheme == 'data' ||
                    scheme == 'blob') {
                  return NavigationActionPolicy.CANCEL;
                }
              }
              return NavigationActionPolicy.ALLOW;
            },
            onCreateWindow: (controller, createWindowAction) async {
              // Open popup/new-window targets (e.g. OAuth "Continue with ...")
              // inside the main WebView instead of dropping them.
              final url = createWindowAction.request.url;
              if (url != null) {
                controller.loadUrl(urlRequest: URLRequest(url: url));
              }
              return false;
            },
          ),
        ),
        if (_loadError != null && !_isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: CustomErrorWidget(
                message: _loadError!,
                onRetry: _retryLoad,
              ),
            ),
          ),
        if (_isLoading)
          Positioned(
            top: 60,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 206,
          right: 16,
          child: GestureDetector(
            onTap: _showOptionsModal,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
              child:
                  const Icon(Icons.more_horiz, color: Colors.white, size: 24),
            ),
          ),
        ),
        Positioned(
          bottom: 164,
          right: 16,
          child: GestureDetector(
            onTap: showMiniPlayer,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.play_circle_outline,
                  color: Colors.white, size: 24),
            ),
          ),
        ),
        Positioned(
          bottom: 122,
          right: 16,
          child: GestureDetector(
            onTap: togglePictureInPicture,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.picture_in_picture_alt,
                  color: Colors.white, size: 24),
            ),
          ),
        ),
        Positioned(
          bottom: 80,
          right: 16,
          child: GestureDetector(
            onTap: () {
              _webViewController?.loadUrl(
                urlRequest: URLRequest(url: WebUri('about:blank')),
              );
              _webViewController = null;
              PlaybackStatsService.instance.flush();
              MediaControlsService.instance.clearNowPlaying();
              ref.read(playerProvider.notifier).dismiss();
              setState(() {
                isReady = false;
                _isLoading = false;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 24),
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetMenuItem extends StatelessWidget {
  const _SheetMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}
