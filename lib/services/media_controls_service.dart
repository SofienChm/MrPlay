import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'picture_in_picture_service.dart';

/// Bridges to the native `com.mrplay/media` channel (iOS only).
///
/// Populates MPNowPlayingInfoCenter (lock screen / Control Center) and
/// forwards remote command events (play/pause/skip/seek) back to Dart.
///
/// IMPORTANT: this class owns the only Dart-side MethodCallHandler for the
/// `com.mrplay/media` channel. The native side also pushes `pipModeChanged`
/// events on the same channel (see PictureInPictureService), so they must be
/// dispatched here — a second `setMethodCallHandler` would silently replace
/// these handlers and break remote commands.
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
      switch (call.method) {
        case 'remoteCommand':
          final args = call.arguments as List<dynamic>? ?? const [];
          final command = args.isNotEmpty ? args[0] as String? ?? '' : '';
          Duration? position;
          if (args.length > 1 && args[1] != null) {
            final ms = (args[1] as num).toDouble();
            position = Duration(milliseconds: ms.round());
          }
          _remoteHandler?.call(command, position: position);
          break;
        case 'pipModeChanged':
          PictureInPictureService.instance.isInPip.value =
              call.arguments == true;
          break;
      }
    });
  }

  /// Full update including artwork. Call when a new video starts.
  Future<void> updateNowPlaying({
    required String title,
    required String artist,
    required Duration position,
    required Duration duration,
    required bool isPlaying,
    String? artworkUrl,
  }) async {
    // Publish the metadata immediately so the lock-screen / notification title
    // shows right away; the artwork is fetched afterwards and applied without
    // blocking the first update (the fetch can take seconds or fail).
    await _setNowPlaying(
      title: title,
      artist: artist,
      position: position,
      duration: duration,
      isPlaying: isPlaying,
      artworkUrl: artworkUrl,
    );
    if (artworkUrl != null && artworkUrl.isNotEmpty) {
      final artwork = await _fetchArtwork(artworkUrl);
      if (artwork != null) {
        await _setNowPlaying(
          title: title,
          artist: artist,
          position: position,
          duration: duration,
          isPlaying: isPlaying,
          artworkUrl: artworkUrl,
          artwork: artwork,
        );
      }
    }
  }

  Future<void> _setNowPlaying({
    required String title,
    required String artist,
    required Duration position,
    required Duration duration,
    required bool isPlaying,
    String? artwork,
    String? artworkUrl,
  }) async {
    try {
      await _channel.invokeMethod('setNowPlaying', {
        'title': title,
        'artist': artist,
        'positionMs': position.inMilliseconds.toDouble(),
        'durationMs': duration.inMilliseconds.toDouble(),
        'isPlaying': isPlaying,
        if (artwork != null) 'artwork': artwork,
        if (artworkUrl != null && artworkUrl.isNotEmpty) 'artworkUrl': artworkUrl,
      });
    } catch (_) {}
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
    } catch (_) {}
  }

  /// Tells the native side whether background audio is allowed. Off => the
  /// foreground service / media notification must not keep running while the
  /// app is backgrounded (the WebView audio is paused by Dart). No-op on iOS
  /// (unhandled channel method).
  Future<void> setBackgroundAudioEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setBackgroundAudioEnabled', enabled);
    } catch (_) {}
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
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}
