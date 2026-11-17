import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/log.dart';
import '../../core/utils/url_utils.dart';

@immutable
class ResolvedLink {
  const ResolvedLink({
    required this.title,
    required this.thumbnailUrl,
    required this.channel,
    required this.url,
    required this.platform,
    required this.videoId,
  });

  final String title;
  final String thumbnailUrl;
  final String channel;
  final String url;
  final String platform;
  final String videoId;
}

final linkResolverProvider = Provider((ref) => LinkResolver());

/// Turns a shared link into a canonical URL plus title/thumbnail metadata.
class LinkResolver {
  static const _oEmbed = 'https://www.youtube.com/oembed';

  static String detectPlatform(String url) {
    if (url.contains('youtube.com/watch') || url.contains('youtu.be/')) return 'YouTube';
    if (url.contains('twitch.tv/videos/') || url.contains('clips.twitch.tv/')) return 'Twitch';
    if (url.contains('rumble.com/')) return 'Rumble';
    if (url.contains('instagram.com')) return 'Instagram';
    if (url.contains('tiktok.com')) return 'TikTok';
    return 'Web';
  }

  static String canonicalUrl(String platform, String videoId, String original) {
    if (videoId.isEmpty) return original;
    switch (platform) {
      case 'YouTube':
        return UrlUtils.isMusic(original)
            ? 'https://music.youtube.com/watch?v=$videoId'
            : 'https://m.youtube.com/watch?v=$videoId';
      case 'Twitch':
        return original.contains('clips.twitch.tv')
            ? 'https://clips.twitch.tv/$videoId'
            : 'https://m.twitch.tv/videos/$videoId';
      default:
        return original;
    }
  }

  static String thumbnail(String platform, String videoId) {
    if (videoId.isEmpty) return '';
    if (platform == 'YouTube') return UrlUtils.youTubeThumbnail(videoId);
    return '';
  }

  Future<ResolvedLink> resolve(String url) async {
    final platform = detectPlatform(url);
    final videoId = platform == 'YouTube' ? (UrlUtils.youTubeId(url) ?? '') : (UrlUtils.videoId(url) ?? '');
    final canonical = canonicalUrl(platform, videoId, url);
    final thumb = thumbnail(platform, videoId);

    if (platform == 'YouTube' && videoId.isNotEmpty) {
      final meta = await _youTubeMeta(canonical);
      if (meta != null) {
        return ResolvedLink(
          title: meta.title,
          thumbnailUrl: thumb,
          channel: meta.channel,
          url: canonical,
          platform: platform,
          videoId: videoId,
        );
      }
    }
    return ResolvedLink(
      title: url,
      thumbnailUrl: thumb,
      channel: platform == 'Web' ? '' : platform,
      url: canonical,
      platform: platform,
      videoId: videoId,
    );
  }

  Future<({String title, String channel})?> _youTubeMeta(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse('$_oEmbed?url=${Uri.encodeComponent(url)}&format=json');
      final response = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is! Map) return null;
      return (
        title: data['title'] as String? ?? url,
        channel: data['author_name'] as String? ?? '',
      );
    } on Exception catch (e) {
      log('oEmbed failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
