import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Layout state of the browser layer that sits above the hub.
@immutable
class BrowserState {
  const BrowserState({
    this.visible = false,
    this.browseUrl,
    this.videoTabUrl,
    this.videoTabId = 0,
    this.pageLoading = false,
    this.platformLoading = false,
    this.error,
  });

  /// The browser layer covers the hub.
  final bool visible;

  /// Page shown in the browse tab (null: nothing loaded, tab stays offstage).
  final String? browseUrl;

  /// Watch URL of the dedicated YouTube video tab (null: no tab).
  final String? videoTabUrl;

  /// Bumped every time a new video tab is created, so its webview gets a
  /// fresh key (and the intro animation replays).
  final int videoTabId;

  /// Small corner spinner while a page loads.
  final bool pageLoading;

  /// Full-screen loader from a hub tap until the first page finishes.
  final bool platformLoading;

  final String? error;

  bool get hasVideoTab => videoTabUrl != null;

  BrowserState copyWith({
    bool? visible,
    String? browseUrl,
    bool clearBrowseUrl = false,
    String? videoTabUrl,
    bool clearVideoTab = false,
    int? videoTabId,
    bool? pageLoading,
    bool? platformLoading,
    String? error,
    bool clearError = false,
  }) =>
      BrowserState(
        visible: visible ?? this.visible,
        browseUrl: clearBrowseUrl ? null : (browseUrl ?? this.browseUrl),
        videoTabUrl: clearVideoTab ? null : (videoTabUrl ?? this.videoTabUrl),
        videoTabId: videoTabId ?? this.videoTabId,
        pageLoading: pageLoading ?? this.pageLoading,
        platformLoading: platformLoading ?? this.platformLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

final browserProvider = NotifierProvider<BrowserNotifier, BrowserState>(BrowserNotifier.new);

/// State holder only; navigation logic lives in [PlaybackEngine].
class BrowserNotifier extends Notifier<BrowserState> {
  @override
  BrowserState build() => const BrowserState();

  void set(BrowserState Function(BrowserState s) change) => state = change(state);
}

/// True while the hub is the visible layer (drives which ad slot shows).
final hubVisibleProvider = Provider<bool>((ref) => !ref.watch(browserProvider).visible);
