import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/utils/log.dart';

/// The two kinds of webview: the browse tab (any site) and the dedicated
/// YouTube video tab.
enum WebTab { browse, video }

/// Injected scripts, loaded once from `assets/js/` at startup.
class WebScripts {
  WebScripts._(this._sources);

  static const _files = [
    'runtime',
    'media_session_bridge',
    'youtube_keepalive',
    'youtube_cleanup',
    'youtube_player_controls',
    'video_tab',
    'media_observer',
    'adblock',
    'popup_blocker',
  ];

  static const adBlockGroup = 'mrplay-adblock';
  static const popupGroup = 'mrplay-popups';

  final Map<String, String> _sources;

  static Future<WebScripts> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    final entries = await Future.wait(
      _files.map((f) async => MapEntry(f, await b.loadString('assets/js/$f.js'))),
    );
    return WebScripts._(Map.fromEntries(entries));
  }

  String source(String name) => _sources[name] ?? '';

  String get adBlock => source('adblock');
  String get popupBlocker => source('popup_blocker');
  String get videoTab => source('video_tab');

  UserScript _script(String name, {String? group, bool mainFrameOnly = true}) => UserScript(
        source: source(name),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        groupName: group,
        forMainFrameOnly: mainFrameOnly,
      );

  UserScript get adBlockScript => _script('adblock', group: adBlockGroup);

  UserScript get popupScript => _script('popup_blocker', group: popupGroup, mainFrameOnly: false);

  /// Initial user scripts for a webview. Order matters: the runtime first,
  /// since every other script talks to the app through `window.__mr`.
  UnmodifiableListView<UserScript> forTab(
    WebTab tab, {
    required bool adBlock,
    required bool blockPopups,
  }) =>
      UnmodifiableListView([
        _script('runtime'),
        if (adBlock) adBlockScript,
        if (blockPopups) popupScript,
        _script('media_session_bridge'),
        _script('youtube_keepalive'),
        _script('youtube_cleanup'),
        _script('youtube_player_controls'),
        _script('media_observer'),
        if (tab == WebTab.video) _script('video_tab'),
      ]);

  /// Switches ad blocking on a live page without reloading (which would
  /// interrupt playback). The script is idempotent and honours the off flag.
  Future<void> applyAdBlock(InAppWebViewController c, {required bool enabled}) async {
    try {
      if (enabled) {
        await c.addUserScript(userScript: adBlockScript);
        await c.evaluateJavascript(source: 'window.__mrAdBlockOff = false;');
        await c.evaluateJavascript(source: adBlock);
      } else {
        await c.removeUserScriptsByGroupName(groupName: adBlockGroup);
        await c.evaluateJavascript(source: 'window.__mrAdBlockOff = true;');
      }
    } on Exception catch (e) {
      log('apply ad-block failed: $e');
    }
  }

  Future<void> applyPopupBlock(InAppWebViewController c, {required bool enabled}) async {
    try {
      if (enabled) {
        await c.addUserScript(userScript: popupScript);
        await c.evaluateJavascript(source: 'window.__mrPopupOff = false;');
        await c.evaluateJavascript(source: popupBlocker);
      } else {
        await c.removeUserScriptsByGroupName(groupName: popupGroup);
        await c.evaluateJavascript(source: 'window.__mrPopupOff = true;');
      }
    } on Exception catch (e) {
      log('apply popup-block failed: $e');
    }
  }
}
