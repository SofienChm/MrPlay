import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:audio_session/audio_session.dart';
import '../../core/constants/youtube_js.dart';
import '../../core/constants/content_blocker_js.dart';
import '../../models/video.dart';
import '../../providers/player_provider.dart';
import '../../services/background_audio_keep_alive.dart';
import '../../services/media_controls_service.dart';
import '../../services/playback_stats_service.dart';
import '../../data/repositories/queue_repository.dart';
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
  // Whether a system-forced pause (iOS suspends the webview's video when the
  // app backgrounds / the screen locks) may be auto-resumed to keep audio
  // playing. User-initiated pauses (lock screen, Control Center, sleep timer)
  // clear this so they are not fought.
  bool _backgroundResumeAllowed = false;
  bool _userPausedInBackground = false;
  int _lastNowPlayingMs = 0;
  Timer? _alignmentWatchdog;
  // Whether the active PiP session was explicitly requested by the user (PiP
  // button / swipe-down-to-PiP). iOS can leave a video stuck in PiP
  // presentation mode after the PiP window is dismissed - the in-page player
  // then stays black while audio and the HTML controls keep working. PiP
  // reports that were NOT requested are forced back inline (see
  // [_onVideoState]); requested ones are left alone.
  bool _pipRequestedByUser = false;
  bool _lastReportedPip = false;

  /// True when the video is actively in PiP (user or auto-background).
  bool get isInPictureInPicture => _pipRequestedByUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MediaControlsService.instance.setRemoteCommandHandler(_onRemoteCommand);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadingTimer?.cancel();
    _nowPlayingThrottle?.cancel();
    _alignmentWatchdog?.cancel();
    PlaybackStatsService.instance.flush();
    BackgroundAudioKeepAlive.instance.stop();
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
      _userPausedInBackground = false;
      _pipRequestedByUser = false;
      _lastReportedPip = false;
      Future.delayed(const Duration(milliseconds: 3000), ensureVideoVisible);
    }
  }

  void _enterBackground() {
    _appIsBackgrounded = true;
    _backgroundResumeAllowed =
        ref.read(playerProvider).isPlaying && !_userPausedInBackground;
    _reassertAudioSession();
    if (ref.read(playerProvider).isPlaying) {
      BackgroundAudioKeepAlive.instance.start();
      enterPiP(resumePlayback: true);
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
          _userPausedInBackground = false;
          _pipRequestedByUser = false;
          _lastReportedPip = false;
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
          if (current != null && current.title == 'YouTube video') {
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
      final pip = data['pip'] == true;
      final pipStuck = data['pipStuck'] == true;
      _lastReportedPip = pip;
      // Stuck-PiP rescue: iOS leaves webkitPresentationMode == 'picture-in-picture'
      // after the PiP window is dismissed, rendering the in-page video black.
      // Only rescue genuinely stuck mode — NOT when the user just requested PiP.
      // On iOS, pipStuck is always true when in PiP mode (pictureInPictureElement
      // doesn't exist), so we must respect _pipRequestedByUser.
      if (pipStuck && !_appIsBackgrounded && !_pipRequestedByUser) {
        ensureVideoVisible();
      } else if (pip && !_pipRequestedByUser && !_appIsBackgrounded) {
        ensureVideoVisible();
      }
      // When the video exits PiP mode entirely (pip goes from true to false),
      // the PiP window was dismissed. Clear the user-requested flag.
      if (!pip && _pipRequestedByUser) {
        _pipRequestedByUser = false;
      }
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
      if (playing && !ended) {
        BackgroundAudioKeepAlive.instance.start();
        _userPausedInBackground = false;
      } else if (!_appIsBackgrounded) {
        // While the app is backgrounded, iOS may pause the webview video
        // momentarily (before/around PiP takeover). Don't kill the keep-alive
        // loop then, or the app gets suspended and audio stops.
        BackgroundAudioKeepAlive.instance.stop();
        if (ended) {
          PlaybackStatsService.instance.flush();
          final id = video?.id ?? '';
          if (id.isNotEmpty) PlaybackStatsService.instance.clearProgress(id);
          _handleEnded();
        }
      } else if (!ended && _backgroundResumeAllowed && data['pip'] != true) {
        // Backgrounded / screen locked and iOS force-paused the webview video
        // (PiP could not take over, e.g. on the lock screen). Resume it so the
        // audio keeps playing; the keep-alive loop holds the process alive and
        // the .playback audio session carries the sound. A pause reported
        // while in PiP is the user pressing the PiP window's pause button -
        // that one must not be resumed.
        controlVideo('play');
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
    if (idMatch == null) return null;
    final videoId = idMatch.group(1)!;
    final video = Video(
      id: videoId,
      title: 'YouTube video',
      thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      videoUrl: url,
      platform: 'YouTube',
    );
    ref.read(playerProvider.notifier).play(video);
    _userPausedInBackground = false;
    _pipRequestedByUser = false;
    _lastReportedPip = false;
    return video;
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
        _backgroundResumeAllowed = true;
        _userPausedInBackground = false;
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
          _backgroundResumeAllowed = true;
          _userPausedInBackground = false;
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
  /// / sleep timer). While backgrounded, system-forced pauses are auto-resumed
  /// to keep audio playing; user pauses must not be fought.
  void userInitiatedPause() {
    _backgroundResumeAllowed = false;
    if (_appIsBackgrounded) _userPausedInBackground = true;
    ref.read(playerProvider.notifier).pause();
    controlVideo('pause');
  }

  /// Shows the mini player: tracks the currently-playing video if needed (so
  /// there is something to display) and collapses the full player. Bound to
  /// the mini-player overlay button in the webview.
  void showMiniPlayer() {
    _userPausedInBackground = false;
    _trackVideoFromUrl();
    if (ref.read(playerProvider).currentVideo != null) {
      ref.read(playerProvider.notifier).minimize();
    }
  }

  void _showOptionsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
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
                    icon: Icons.settings,
                    label: 'Settings',
                    onTap: () => Navigator.pop(sheetContext),
                  ),
                  const Divider(color: Colors.white10, height: 1, indent: 56),
                  _SheetMenuItem(
                    icon: Icons.share,
                    label: 'Share',
                    onTap: () => Navigator.pop(sheetContext),
                  ),
                  const Divider(color: Colors.white10, height: 1, indent: 56),
                  _SheetMenuItem(
                    icon: Icons.airplay,
                    label: 'AirPlay',
                    onTap: () => Navigator.pop(sheetContext),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Full cleanup: pauses the video, cancels timers, stops audio keep-alive,
  /// clears now-playing, flushes stats, and dismisses the player state.
  void closePlayer() {
    controlVideo('pause');
    stopVideoAlignmentWatchdog();
    _loadingTimer?.cancel();
    _loadingTimer = null;
    _nowPlayingThrottle?.cancel();
    _nowPlayingThrottle = null;
    BackgroundAudioKeepAlive.instance.stop();
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
            var v = document.querySelector('video');
            if (v) v.play().catch(function(){});
          })();
        ''');
        break;
      case 'pause':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = document.querySelector('video');
            if (v) v.pause();
          })();
        ''');
        break;
      case 'seek':
        if (position != null) {
          controller.evaluateJavascript(source: '''
            (function() {
              var v = document.querySelector('video');
              if (v) v.currentTime = $position;
            })();
          ''');
        }
        break;
      case 'toggleCaptions':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = document.querySelector('video');
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
            var v = document.querySelector('video');
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

  void enterPiP({bool resumePlayback = false}) {
    _pipRequestedByUser = true;
    _webViewController?.evaluateJavascript(source: '''
      (function() {
        var video = document.querySelector('video');
        if (!video) return;
        if (video.requestPictureInPicture) {
          if (document.pictureInPictureElement) return;
          video.requestPictureInPicture().catch(function(){});
        } else if (video.webkitSetPresentationMode) {
          if (video.webkitPresentationMode !== 'picture-in-picture') {
            video.webkitSetPresentationMode('picture-in-picture');
          }
        }
        if ($resumePlayback) {
          if (video.paused) {
            video.play().catch(function() {
              var btn = document.querySelector('.ytp-play-button');
              if (btn) btn.click();
            });
          }
        }
      })();
    ''');
  }

  /// Brings the playing <video> back into the visible viewport. Used when the
  /// full player is expanded so the live video (rendered by the webview) lines
  /// up with the transparent video area of the full player.
  void scrollVideoIntoView() {
    _webViewController?.evaluateJavascript(source: '''
      (function() {
        var v = document.querySelector('video');
        if (!v) return;
        var player = v.closest('#movie_player') || v.parentElement;
        if (!player) return;
        var r = player.getBoundingClientRect();
        var targetY = window.scrollY + r.top - 47;
        if (targetY < 0) targetY = 0;
        window.scrollTo({top: targetY, behavior: 'smooth'});
      })();
    ''');
  }

  /// Brings the playing <video> back inline after auto-PiP on backgrounding.
  /// Without this, returning to the app leaves the in-page player black while
  /// the video keeps floating in the PiP window.
  void exitPiP() {
    _pipRequestedByUser = false;
    _lastReportedPip = false;
    _webViewController?.evaluateJavascript(source: '''
      (function() {
        var video = document.querySelector('video');
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

  /// Last-resort fallback: if exitPiP failed to bring the video back inline,
  /// force the video element to be visible so the user doesn't see a black
  /// screen. Tries webkitSetPresentationMode('inline'), then falls back to a
  /// DOM reinsertion trick — removing the <video> from the DOM and putting it
  /// back forces iOS to reset the presentation pipeline, which is more
  /// reliable than the API call (which iOS can silently ignore).
  void ensureVideoVisible() {
    _pipRequestedByUser = false;
    _lastReportedPip = false;
    _webViewController?.evaluateJavascript(source: '''
      (function() {
        var video = document.querySelector('video');
        if (!video) return;
        try {
          if (video.webkitSetPresentationMode &&
              video.webkitPresentationMode === 'picture-in-picture') {
            video.webkitSetPresentationMode('inline');
          }
        } catch (e) {}
        video.style.setProperty('visibility', 'visible', 'important');
        video.style.setProperty('opacity', '1', 'important');
        video.style.removeProperty('display');
        video.style.removeProperty('clip');
        video.style.removeProperty('clip-path');
        video.style.removeProperty('width');
        video.style.removeProperty('height');
        video.style.setProperty('object-fit', 'contain', 'important');
        var player = document.querySelector('#movie_player');
        if (player) {
          var pipPlaceholder = player.querySelector('.ytp-pip-container, [class*="pip"]');
          if (pipPlaceholder) pipPlaceholder.remove();
          var poster = player.querySelector('.ytp-cued-thumbnail-overlay, .ytp-poster, .ytp-cued-thumbnail-overlay-image, [class*="thumbnail"][class*="overlay"]');
          if (poster) poster.style.display = 'none';
        }
        // Scroll the video into the viewport in case the player layout
        // was broken (e.g. by the old #movie_player position override).
        var r = video.getBoundingClientRect();
        if (r.height < 10 || r.width < 10 || r.top < -window.innerHeight) {
          var c = player || video.parentElement;
          if (c) {
            var cr = c.getBoundingClientRect();
            var t = window.scrollY + cr.top - 50;
            if (t < 0) t = 0;
            window.scrollTo({top: t, behavior: 'instant'});
          }
        }
        // DOM reinsertion trick: if the video is still stuck in PiP mode after
        // the API call above, briefly remove it from the DOM and reinsert it.
        // This forces iOS WKWebView to tear down and rebuild the presentation
        // pipeline — the only reliable way to escape a stuck presentation mode.
        if (video.webkitPresentationMode === 'picture-in-picture') {
          var parent = video.parentNode;
          if (parent) {
            var wasPlaying = !video.paused;
            var next = video.nextSibling;
            var currentTime = video.currentTime;
            parent.removeChild(video);
            parent.insertBefore(video, next);
            video.currentTime = currentTime;
            if (wasPlaying) {
              video.play().catch(function(){});
            }
          }
        }
      })();
    ''');
  }

  void startVideoAlignmentWatchdog() {
    _alignmentWatchdog?.cancel();
    var ticks = 0;
    _alignmentWatchdog = Timer.periodic(const Duration(milliseconds: 400), (t) {
      scrollVideoIntoView();
      ensureVideoVisible();
      ticks++;
      if (ticks >= 8) t.cancel();
    });
  }

  void stopVideoAlignmentWatchdog() {
    _alignmentWatchdog?.cancel();
    _alignmentWatchdog = null;
  }

  /// Forces the video back inline when the full player collapses to the mini
  /// player, unless PiP is actively showing (user sees a PiP window). Covers
  /// the stuck-PiP case where the black in-page video only becomes visible
  /// again in the PiP window.
  void _unstickPiPIfUnrequested() {
    if (_appIsBackgrounded) return;
    if (_pipRequestedByUser) return;
    ensureVideoVisible();
  }

  void togglePictureInPicture() {
    _pipRequestedByUser = !_lastReportedPip;
    _webViewController?.evaluateJavascript(source: '''
      (function() {
        var video = document.querySelector('video');
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

  @override
  Widget build(BuildContext context) {
    ref.listen(playerProvider, (prev, next) {
      final collapsedToMini = prev?.isMinimized == false && next.isMinimized;
      if (collapsedToMini) _unstickPiPIfUnrequested();
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
              child: const Icon(Icons.more_horiz,
                  color: Colors.white, size: 24),
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
              _pipRequestedByUser = false;
              _lastReportedPip = false;
              BackgroundAudioKeepAlive.instance.stop();
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
