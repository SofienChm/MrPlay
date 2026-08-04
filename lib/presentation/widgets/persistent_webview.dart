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
    PlaybackStatsService.instance.flush();
    BackgroundAudioKeepAlive.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // Enter PiP as early as possible (the `inactive` frame). iOS pauses the
      // webview's video track right around `paused`, and once that happens
      // requestPictureInPicture can refuse, killing background audio.
      _enterBackground();
    } else if (state == AppLifecycleState.paused) {
      _enterBackground();
    } else if (state == AppLifecycleState.resumed) {
      _appIsBackgrounded = false;
      _userPausedInBackground = false;
      // Bring the video back inline. PiP may have been entered while
      // backgrounded (or by a transient `inactive` such as Control Center);
      // leaving it on makes the in-page player a black "playing in PiP"
      // placeholder that survives across videos (the SPA reuses the element).
      // Retry multiple times: the PiP presentation-mode transition is async
      // and can swallow an exit requested while it is still being established.
      exitPiP();
      Future.delayed(const Duration(milliseconds: 600), exitPiP);
      Future.delayed(const Duration(milliseconds: 1500), exitPiP);
      Future.delayed(const Duration(milliseconds: 3000), _ensureVideoVisible);
    }
  }

  void _enterBackground() {
    _appIsBackgrounded = true;
    // Only auto-resume if the video was playing when the app went away and
    // the user hasn't explicitly paused from the background/lock screen.
    _backgroundResumeAllowed = ref.read(playerProvider).isPlaying && !_userPausedInBackground;
    _reassertAudioSession();
    // Keep the audio session alive while the webview is suspended so iOS
    // doesn't tear down background audio before PiP has a chance to take over
    // the video track.
    if (ref.read(playerProvider).isPlaying) {
      BackgroundAudioKeepAlive.instance.start();
    }
    enterPiP(resumePlayback: ref.read(playerProvider).isPlaying && !_userPausedInBackground);
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
        final action = (args.first as Map<String, dynamic>)['action'] as String?;
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

  Future<void> _onLoadStop(InAppWebViewController controller, WebUri? url) async {
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
          PlaybackStatsService.instance.resumePosition(videoId).then((resumeMs) {
            if (resumeMs > 0) {
              Future.delayed(const Duration(milliseconds: 3500), () async {
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
        setState(() => _loadError = 'Could not load the page: ${error.description}');
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
        if (r.top < 0 || r.bottom > window.innerHeight) {
          player.scrollIntoView({block: 'start', behavior: 'smooth'});
        }
      })();
    ''');
  }

  /// Brings the playing <video> back inline after auto-PiP on backgrounding.
  /// Without this, returning to the app leaves the in-page player black while
  /// the video keeps floating in the PiP window.
  void exitPiP() {
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
  /// screen. Also tries one final PiP exit in case the timing was just off.
  void _ensureVideoVisible() {
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
        video.style.visibility = 'visible';
        video.style.opacity = '1';
        video.style.display = '';
        var player = document.querySelector('#movie_player');
        if (player) {
          var pipPlaceholder = player.querySelector('.ytp-pip-container, [class*="pip"]');
          if (pipPlaceholder) pipPlaceholder.remove();
        }
      })();
    ''');
  }

  void togglePictureInPicture() {
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
              source: YouTubeJS.searchSpaScript,
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
              if (scheme != 'http' && scheme != 'https' && scheme != 'about' && scheme != 'file') {
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
          bottom: 170,
          right: 16,
          child: GestureDetector(
            onTap: showMiniPlayer,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 24),
            ),
          ),
        ),
        Positioned(
          bottom: 130,
          right: 16,
          child: GestureDetector(
            onTap: togglePictureInPicture,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D).withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.picture_in_picture_alt, color: Colors.white, size: 24),
            ),
          ),
        ),
        Positioned(
          bottom: 90,
          right: 16,
          child: GestureDetector(
            onTap: () {
              _webViewController?.loadUrl(
                urlRequest: URLRequest(url: WebUri('about:blank')),
              );
              _webViewController = null;
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
