import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_handler.dart';

class MediaManager {
  static final MediaManager _instance = MediaManager._();
  static MediaManager get instance => _instance;
  MediaManager._();

  MrPlayAudioHandler? _handler;

  void init(MrPlayAudioHandler handler) {
    _handler = handler;
  }

  MrPlayAudioHandler? get handler => _handler;

  String videoId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    if (uri.host.contains('youtube') || uri.host.contains('youtu.be')) {
      if (uri.queryParameters.containsKey('v')) return uri.queryParameters['v']!;
      if (uri.host == 'youtu.be') return uri.pathSegments.first;
    }
    return '';
  }

  Future<bool> playWithUrl(String url) async {
    try {
      final source = AudioSource.uri(Uri.parse(url), headers: {
        'Referer': 'https://www.youtube.com/',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 8.0.0; SM-G950W) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.7204.179 Mobile Safari/537.36',
      });
      await _handler?.setSource(source);
      await _handler?.play();
      debugPrint('[MediaManager] playWithUrl succeeded');
      return true;
    } catch (e) {
      debugPrint('[MediaManager] playWithUrl failed: $e');
      return false;
    }
  }

  Future<bool> play(String url) async {
    final id = videoId(url);
    if (id.isEmpty) return false;
    return playWithCookies(id, '');
  }

  Future<bool> playWithCookies(String id, String cookies) async {
    final httpClient = _createHttpClient(cookies);
    final yt = YoutubeExplode(httpClient);
    try {
      final manifest = await yt.videos.streamsClient.getManifest(id);
      final audio = manifest.audioOnly.firstOrNull;
      if (audio == null) {
        debugPrint('[MediaManager] No audio-only stream found');
        return false;
      }
      final source = AudioSource.uri(audio.url);
      await _handler?.setSource(source);
      await _handler?.play();
      debugPrint('[MediaManager] playWithCookies succeeded');
      return true;
    } catch (e) {
      debugPrint('[MediaManager] playWithCookies failed: $e');
      return false;
    } finally {
      yt.close();
    }
  }

  YoutubeHttpClient _createHttpClient(String cookies) {
    final headers = <String, String>{
      'user-agent':
          'Mozilla/5.0 (Linux; Android 8.0.0; SM-G950W) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.7204.179 Mobile Safari/537.36',
      'accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
      'accept-language': 'en-US,en;q=0.9',
      'accept-encoding': 'gzip, deflate, br',
    };
    if (cookies.isNotEmpty) {
      headers['cookie'] = cookies;
    } else {
      headers['cookie'] = 'CONSENT=YES+cb';
    }
    return _CookieHttpClient(headers);
  }

  Future<void> stop() async {
    await _handler?.stop();
  }
}

class _CookieHttpClient extends YoutubeHttpClient {
  final Map<String, String> _headers;

  _CookieHttpClient(this._headers);

  @override
  Map<String, String> get headers => _headers;
}
