import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/utils/log.dart';

/// Result of an async page command (`{ok, reason}` from runtime.js).
typedef BridgeResult = ({bool ok, String reason});

/// Typed commands to the active page's `<video>`, all routed through the
/// `window.__mr` runtime injected by `assets/js/runtime.js`.
class VideoBridge {
  VideoBridge(this._controller);

  /// Resolves the controller of the webview that currently owns playback.
  final InAppWebViewController? Function() _controller;

  Future<Object?> _eval(String call) async {
    final c = _controller();
    if (c == null) return null;
    try {
      return await c.evaluateJavascript(source: 'window.__mr && window.__mr.$call');
    } on Exception catch (e) {
      log('js $call failed: $e');
      return null;
    }
  }

  Future<BridgeResult> _async(String call) async {
    final c = _controller();
    if (c == null) return (ok: true, reason: 'no-webview');
    try {
      final result = await c.callAsyncJavaScript(
        functionBody: 'if (!window.__mr) return {ok: false, reason: "no-runtime"}; return await window.__mr.$call;',
      );
      final value = result?.value;
      if (value is Map) {
        return (ok: value['ok'] == true, reason: '${value['reason']}');
      }
      return (ok: false, reason: 'no-result');
    } on Exception catch (e) {
      // The WebContent process may be suspended or not attached yet.
      return (ok: false, reason: 'error: $e');
    }
  }

  Future<void> play() => _eval('play()');
  Future<void> pause() => _eval('pause()');
  Future<void> seek(Duration position) => _eval('seek(${position.inMilliseconds / 1000.0})');
  Future<void> resumeOrStart() => _eval('resumeOrStart()');
  Future<void> nudge({required bool play}) => _eval('nudge($play)');
  Future<void> softPauseToReal() => _eval('softPauseToReal()');
  Future<void> toggleCaptions() => _eval('toggleCaptions()');
  Future<void> toggleFullscreen() => _eval("fullscreen('toggle')");
  Future<void> enterFullscreen() => _eval("fullscreen('enter')");
  Future<void> exitFullscreen() => _eval("fullscreen('exit')");
  Future<void> togglePip() => _eval('togglePip()');
  Future<void> enterPip() => _eval('enterPip()');
  Future<void> exitPip() => _eval('exitPip()');
  Future<void> forceInline() => _eval('forceInline()');
  Future<void> reassertPhantomPip() => _eval('reassertPhantomPip()');
  Future<void> airplay() => _eval('airplay()');

  /// True when the active video is audible afterwards.
  Future<bool> unmute() async {
    final value = await _eval('unmute()');
    return value is Map && value['audible'] == true;
  }

  Future<Map<String, dynamic>?> state() async {
    final value = await _eval('state()');
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  /// Reports the watch-page title through `playerInfo`; true once done.
  Future<bool> reportWatchInfo(InAppWebViewController c) async {
    try {
      return await c.evaluateJavascript(source: 'window.__mr && window.__mr.reportWatchInfo()') == true;
    } on Exception {
      return false;
    }
  }

  Future<BridgeResult> enterPhantomPip({required bool userPlay}) => _async('enterPhantomPip($userPlay)');

  Future<BridgeResult> restoreInline() => _async('restoreInline()');
}
