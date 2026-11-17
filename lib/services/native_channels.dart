import 'dart:async';
import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/services.dart';

import '../core/config/feature_flags.dart';
import '../core/utils/log.dart';

typedef UrlHandler = void Function(String url);

/// Channel names shared with ios/Runner/AppDelegate.swift.
abstract final class ChannelNames {
  static const spotlight = 'com.mrplay/spotlight';
  static const siri = 'com.mrplay/siri';
  static const media = 'com.mrplay/media';
}

Future<T?> _invoke<T>(MethodChannel channel, String method, [Object? args]) async {
  try {
    return await channel.invokeMethod<T>(method, args);
  } on MissingPluginException {
    return null;
  } on PlatformException catch (e) {
    log('${channel.name}.$method failed: ${e.message}');
    return null;
  }
}

/// Core Spotlight indexing of watched videos.
class SpotlightService {
  SpotlightService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(ChannelNames.spotlight);

  final MethodChannel _channel;

  /// [onOpen] receives the URL of a Spotlight result the user tapped.
  void listen(UrlHandler onOpen) {
    _channel.setMethodCallHandler((call) async {
      final url = call.arguments;
      if (call.method == 'open' && url is String && url.isNotEmpty) onOpen(url);
    });
  }

  Future<void> index({required String title, required String subtitle, required String url}) =>
      _invoke<void>(_channel, 'index', {'title': title, 'subtitle': subtitle, 'url': url});

  Future<void> clear() => _invoke<void>(_channel, 'clear');
}

/// Siri / Shortcuts app "Open (platform) in MrPlay" (NSUserActivity).
class SiriService {
  SiriService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(ChannelNames.siri);

  final MethodChannel _channel;

  Future<void> init({
    required UrlHandler onOpen,
    required List<({String id, String title, String url})> shortcuts,
  }) async {
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      if (call.method == 'onShortcut' && args is Map) {
        final url = args['url'];
        if (url is String && url.isNotEmpty) onOpen(url);
      }
      return null;
    });
    final pending = await _invoke<String>(_channel, 'consumePending');
    if (pending != null && pending.isNotEmpty) onOpen(pending);
    await _invoke<void>(_channel, 'register', {
      'shortcuts': [
        for (final s in shortcuts) {'id': s.id, 'title': s.title, 'url': s.url},
      ],
    });
  }

  /// Lets iOS suggest the last-used platform on the lock screen.
  Future<void> donate({required String name, required String url}) =>
      _invoke<void>(_channel, 'setCurrent', {'name': name, 'url': url});
}

/// MPNowPlayingInfoCenter bridge. Only active when
/// [FeatureFlags.nativeLockScreen] is on; otherwise WebKit owns Now Playing and
/// only the headphone-disconnect pause comes through [listen].
class NowPlayingService {
  NowPlayingService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(ChannelNames.media);

  final MethodChannel _channel;
  int _artworkGeneration = 0;

  void listen(void Function(String command, Duration? position) onCommand) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'remoteCommand') return;
      final args = call.arguments;
      if (args is! List || args.isEmpty || args.first is! String) return;
      final ms = args.length > 1 && args[1] is num ? (args[1] as num).toDouble() : null;
      onCommand(args.first as String, ms == null ? null : Duration(milliseconds: ms.round()));
    });
  }

  Future<void> setTrack({
    required String title,
    required String artist,
    String? artworkUrl,
  }) async {
    if (!FeatureFlags.nativeLockScreen) return;
    final generation = ++_artworkGeneration;
    await _invoke<void>(_channel, 'setNowPlaying', {
      'title': title,
      'artist': artist,
      'positionMs': 0.0,
      'durationMs': 0.0,
      'isPlaying': true,
    });
    if (artworkUrl == null || artworkUrl.isEmpty) return;
    final artwork = await _fetchBase64(artworkUrl);
    if (artwork == null || generation != _artworkGeneration) return;
    await _invoke<void>(_channel, 'setNowPlaying', {'artwork': artwork});
  }

  Future<void> setProgress({
    required Duration position,
    required Duration duration,
    required bool isPlaying,
  }) async {
    if (!FeatureFlags.nativeLockScreen) return;
    await _invoke<void>(_channel, 'setNowPlaying', {
      'positionMs': position.inMilliseconds.toDouble(),
      'durationMs': duration.inMilliseconds.toDouble(),
      'isPlaying': isPlaying,
    });
  }

  Future<void> clear() async {
    if (!FeatureFlags.nativeLockScreen) return;
    _artworkGeneration++;
    await _invoke<void>(_channel, 'clearNowPlaying');
  }

  Future<String?> _fetchBase64(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final response = await (await client.getUrl(Uri.parse(url))).close();
      if (response.statusCode != HttpStatus.ok) return null;
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add);
      return base64Encode(builder.takeBytes());
    } on Exception catch (e) {
      log('artwork fetch failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
