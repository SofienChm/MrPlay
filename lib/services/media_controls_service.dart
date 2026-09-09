import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges to the native `com.mrplay/media` channel (iOS only).
///
/// Populates MPNowPlayingInfoCenter (lock screen / Control Center) and
/// forwards remote command events (play/pause/skip/seek) back to Dart.
class MediaControlsService {
  MediaControlsService._();

  static final MediaControlsService instance = MediaControlsService._();

  static const MethodChannel _channel = MethodChannel('com.mrplay/media');

  void Function(String command, {Duration? position})? _remoteHandler;

  void setRemoteCommandHandler(
    void Function(String command, {Duration? position}) handler,
  ) {
    _remoteHandler = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'remoteCommand') return;
      final args = call.arguments as List<dynamic>? ?? const [];
      final command = args.isNotEmpty ? args[0] as String? ?? '' : '';
      Duration? position;
      if (args.length > 1 && args[1] != null) {
        final ms = (args[1] as num).toDouble();
        position = Duration(milliseconds: ms.round());
      }
      _remoteHandler?.call(command, position: position);
    });
  }

  /// Full update including artwork. Sends metadata immediately, then updates
  /// with artwork when the fetch completes (non-blocking).
  Future<void> updateNowPlaying({
    required String title,
    required String artist,
    required Duration position,
    required Duration duration,
    required bool isPlaying,
    String? artworkUrl,
  }) async {
    try {
      await _channel.invokeMethod('setNowPlaying', {
        'title': title,
        'artist': artist,
        'positionMs': position.inMilliseconds.toDouble(),
        'durationMs': duration.inMilliseconds.toDouble(),
        'isPlaying': isPlaying,
      });
    } catch (e) {
      debugPrint('[MrPlay] setNowPlaying failed: $e');
    }

    if (artworkUrl != null && artworkUrl.isNotEmpty) {
      _fetchArtwork(artworkUrl).then((artwork) {
        if (artwork == null) return;
        try {
          _channel.invokeMethod('setNowPlaying', {
            'artwork': artwork,
          });
        } catch (e) {
          debugPrint('[MrPlay] artwork update failed: $e');
        }
      });
    }
  }

  /// Lightweight progress update (no artwork). Throttle callers.
  Future<void> updateProgress({
    required Duration position,
    required Duration duration,
    required bool isPlaying,
  }) async {
    try {
      await _channel.invokeMethod('setNowPlaying', {
        'positionMs': position.inMilliseconds.toDouble(),
        'durationMs': duration.inMilliseconds.toDouble(),
        'isPlaying': isPlaying,
      });
    } catch (_) {}
  }

  Future<void> setPlaying(bool isPlaying) async {
    try {
      await _channel.invokeMethod('setPlaying', {'isPlaying': isPlaying});
    } catch (_) {}
  }

  Future<void> clearNowPlaying() async {
    try {
      await _channel.invokeMethod('clearNowPlaying');
    } catch (e) {
      debugPrint('[MrPlay] clearNowPlaying failed: $e');
    }
  }

  Future<String?> _fetchArtwork(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return null;
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('[MrPlay] artwork fetch failed: $e');
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}
