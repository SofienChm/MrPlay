import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/app_info.dart';
import '../../core/theme/palettes.dart';
import '../player/options_sheet.dart';
import '../player/playback_engine.dart';
import '../player/player_state.dart';
import 'browser_state.dart';
import 'web_scripts.dart';

/// The browser layer above the hub: the browse webview, the YouTube video
/// tab on top of it, loaders/errors, and the floating action buttons.
class BrowserLayer extends ConsumerWidget {
  const BrowserLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final browser = ref.watch(browserProvider);
    if (!browser.visible) return const SizedBox.shrink();
    final player = ref.watch(playerProvider);
    final tabCollapsed = browser.hasVideoTab && player.isVideoTab && player.isMinimized;

    return Stack(
      children: [
        // Kept offstage until it holds a page, so playing straight from the
        // library doesn't paint an empty white webview under the video tab.
        Positioned.fill(
          child: Offstage(
            offstage: browser.browseUrl == null,
            child: const _EngineWebView(tab: WebTab.browse),
          ),
        ),
        if (browser.hasVideoTab)
          Positioned.fill(
            child: _VideoTab(
              key: ValueKey('video-tab-${browser.videoTabId}'),
              collapsed: tabCollapsed,
              url: browser.videoTabUrl!,
            ),
          ),
        if (browser.error != null && !browser.pageLoading)
          Positioned.fill(child: _ErrorView(message: browser.error!)),
        if (browser.platformLoading && browser.error == null) const Positioned.fill(child: _PlatformLoader()),
        if (browser.pageLoading && !browser.platformLoading) const _CornerSpinner(),
        if (browser.hasVideoTab && !tabCollapsed) const _CollapseHandle(),
        _FloatingActions(liftForMiniBar: tabCollapsed),
      ],
    );
  }
}

/// One InAppWebView wired to the [PlaybackEngine].
class _EngineWebView extends ConsumerWidget {
  const _EngineWebView({required this.tab, this.initialUrl});

  final WebTab tab;
  final String? initialUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(playbackEngineProvider);
    // Read once: later toggles are applied live by the engine, rebuilding
    // the webview would cut playback.
    final settings = ref.read(settingsProvider);
    return InAppWebView(
      initialUrlRequest: initialUrl == null ? null : URLRequest(url: WebUri(initialUrl!)),
      initialUserScripts: engine.scripts.forTab(
        tab,
        adBlock: settings.adBlock,
        blockPopups: settings.blockPopups,
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,
        allowBackgroundAudioPlaying: true,
        allowsPictureInPictureMediaPlayback: true,
        allowsAirPlayForMediaPlayback: true,
        isFraudulentWebsiteWarningEnabled: false,
        supportMultipleWindows: true,
        userAgent: AppInfo.webUserAgent,
      ),
      onWebViewCreated: (c) => engine.onWebViewCreated(tab, c),
      onLoadStart: (_, url) => engine.onLoadStart(tab, url?.toString()),
      onLoadStop: (c, url) => engine.onLoadStop(tab, c, url?.toString()),
      onUpdateVisitedHistory: (c, url, _) => engine.onVisitedHistory(tab, c, url?.toString()),
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame != false) {
          engine.onMainFrameError('Could not load the page: ${error.description}');
        }
      },
      onReceivedHttpError: (_, request, response) {
        if (request.isForMainFrame != false) {
          engine.onMainFrameError('Server error ${response.statusCode ?? 'unknown'}');
        }
      },
      shouldOverrideUrlLoading: (_, action) async => engine.shouldOverrideUrlLoading(action.request.url),
      onCreateWindow: (c, action) async => engine.onCreateWindow(c, action),
      onWebContentProcessDidTerminate: (c) => unawaited(engine.onProcessTerminated(tab, c)),
    );
  }
}

/// The dedicated YouTube tab. Never disposed while playing (that would cut
/// the audio): when collapsed it fades out and ignores touches instead.
class _VideoTab extends ConsumerStatefulWidget {
  const _VideoTab({super.key, required this.collapsed, required this.url});

  final bool collapsed;
  final String url;

  @override
  ConsumerState<_VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends ConsumerState<_VideoTab> {
  /// Slide-in from the bottom whenever a new video is opened.
  bool _intro = true;

  @override
  void initState() {
    super.initState();
    _playIntro();
  }

  @override
  void didUpdateWidget(_VideoTab old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url && !widget.collapsed) _playIntro();
    if (old.collapsed && !widget.collapsed) ref.read(playbackEngineProvider).onVideoTabExpanded();
  }

  void _playIntro() {
    _intro = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _intro = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 300);
    final hidden = widget.collapsed || _intro;
    return IgnorePointer(
      ignoring: widget.collapsed,
      child: AnimatedOpacity(
        opacity: hidden ? 0 : 1,
        duration: duration,
        curve: Curves.easeInOut,
        child: AnimatedSlide(
          offset: _intro ? const Offset(0, 0.35) : (widget.collapsed ? const Offset(0, 0.25) : Offset.zero),
          duration: duration,
          curve: Curves.easeInOut,
          // The URL only seeds the first load; later videos are navigated by
          // the engine without rebuilding the webview.
          child: _EngineWebView(tab: WebTab.video, initialUrl: widget.url),
        ),
      ),
    );
  }
}

/// Full-width drag strip at the top of the expanded video tab.
class _CollapseHandle extends ConsumerStatefulWidget {
  const _CollapseHandle();

  @override
  ConsumerState<_CollapseHandle> createState() => _CollapseHandleState();
}

class _CollapseHandleState extends ConsumerState<_CollapseHandle> {
  double _offset = 0;

  void _collapse() {
    setState(() => _offset = 0);
    ref.read(playbackEngineProvider).minimizeVideoTab();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 6,
      left: 0,
      right: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _collapse,
        onVerticalDragUpdate: (d) => setState(() => _offset = (_offset + d.delta.dy).clamp(0, 400)),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 350 || _offset > 110) {
            _collapse();
          } else {
            setState(() => _offset = 0);
          }
        },
        child: SizedBox(
          height: 44,
          child: Center(
            child: Transform.translate(
              offset: Offset(0, _offset),
              child: AnimatedOpacity(
                opacity: _offset > 20 ? 0.3 : 1,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  width: 128,
                  height: 34,
                  decoration: BoxDecoration(
                    color: PlayerColors.sheet.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 26),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Options / mini player / PiP / close buttons on the right edge.
class _FloatingActions extends ConsumerWidget {
  const _FloatingActions({required this.liftForMiniBar});

  /// Sit above the collapsed video tab's mini bar (YouTube nav 52 + bar 64).
  final bool liftForMiniBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(playbackEngineProvider);
    final base = liftForMiniBar ? 52 + MediaQuery.paddingOf(context).bottom + 64 + 12 : 80.0;
    final buttons = <(IconData, String, VoidCallback)>[
      (Icons.close, 'Back to hub', engine.goHub),
      (Icons.picture_in_picture_alt, 'Picture in picture', engine.togglePip),
      (Icons.play_circle_outline, 'Mini player', engine.showMiniPlayer),
      (Icons.more_horiz, 'More options', () => showOptionsSheet(context)),
    ];
    return Positioned(
      right: 16,
      bottom: base,
      child: Column(
        verticalDirection: VerticalDirection.up,
        children: [
          for (final (icon, label, onTap) in buttons)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _RoundButton(icon: icon, tooltip: label, onTap: onTap),
            ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: PlayerColors.chip.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _PlatformLoader extends ConsumerWidget {
  const _PlatformLoader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          const Center(child: CircularProgressIndicator(color: Colors.red, strokeWidth: 3)),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: IconButton(
              tooltip: 'Back to hub',
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: ref.read(playbackEngineProvider).goHub,
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerSpinner extends StatelessWidget {
  const _CornerSpinner();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
        ),
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(playbackEngineProvider);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 56),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(onPressed: engine.goHub, child: const Text('Back to hub')),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: engine.retry, child: const Text('Retry')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
