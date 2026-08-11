import 'dart:convert';
import 'dart:io';

class ResolvedLink {
  final String title;
  final String thumbnailUrl;
  final String channel;
  final String url;
  final String platform;
  final String videoId;

  const ResolvedLink({
    required this.title,
    required this.thumbnailUrl,
    required this.channel,
    required this.url,
    required this.platform,
    required this.videoId,
  });
}

class LinkResolverService {
  LinkResolverService._();
  static final LinkResolverService instance = LinkResolverService._();

  static const _youtubeOEmbed = 'https://www.youtube.com/oembed';

  bool _isYouTube(String url) =>
      url.contains('youtube.com/watch') ||
      url.contains('youtu.be/') ||
      url.contains('m.youtube.com/watch') ||
      url.contains('music.youtube.com/watch');

  bool _isTwitch(String url) =>
      url.contains('twitch.tv/videos/') ||
      url.contains('clips.twitch.tv/');

  bool _isRumble(String url) =>
      url.contains('rumble.com/');

  String? _extractVideoId(String url) {
    var match = RegExp(r'[?&]v=([^&]+)').firstMatch(url);
    if (match != null) return match.group(1);
    match = RegExp(r'youtu\.be/([^?&]+)').firstMatch(url);
    if (match != null) return match.group(1);
    match = RegExp(r'twitch\.tv/videos/(\d+)').firstMatch(url);
    if (match != null) return match.group(1);
    match = RegExp(r'clips\.twitch\.tv/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (match != null) return match.group(1);
    match = RegExp(r'rumble\.com/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (match != null) return match.group(1);
    return null;
  }

  String _detectPlatform(String url) {
    if (_isYouTube(url)) return 'YouTube';
    if (_isTwitch(url)) return 'Twitch';
    if (_isRumble(url)) return 'Rumble';
    if (url.contains('instagram.com')) return 'Instagram';
    if (url.contains('tiktok.com')) return 'TikTok';
    return 'Web';
  }

  String _thumbnailFromId(String platform, String videoId) {
    switch (platform) {
      case 'YouTube':
        return 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      case 'Twitch':
        return 'https://static-cdn.jtvnw.net/previews-ttv/live_user_$videoId-440x248.jpg';
      default:
        return '';
    }
  }

  String _canonicalUrl(String platform, String videoId, String originalUrl) {
    switch (platform) {
      case 'YouTube':
        return 'https://m.youtube.com/watch?v=$videoId';
      case 'Twitch':
        if (originalUrl.contains('clips.twitch.tv')) {
          return 'https://clips.twitch.tv/$videoId';
        }
        return 'https://m.twitch.tv/videos/$videoId';
      case 'Rumble':
        return originalUrl;
      default:
        return originalUrl;
    }
  }

  Future<ResolvedLink?> resolve(String url) async {
    final platform = _detectPlatform(url);
    final videoId = _extractVideoId(url) ?? '';
    final canonicalUrl = _canonicalUrl(platform, videoId, url);
    final thumbnailUrl = _thumbnailFromId(platform, videoId);

    if (platform == 'YouTube' && videoId.isNotEmpty) {
      try {
        final oembedUrl =
            '$_youtubeOEmbed?url=${Uri.encodeComponent(canonicalUrl)}&format=json';
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        try {
          final request = await client.getUrl(Uri.parse(oembedUrl));
          final response = await request.close();
          if (response.statusCode == 200) {
            final body =
                await response.transform(utf8.decoder).join();
            final data = jsonDecode(body) as Map<String, dynamic>;
            final title = (data['title'] as String?) ?? url;
            final channel =
                (data['author_name'] as String?) ?? '';
            return ResolvedLink(
              title: title,
              thumbnailUrl: thumbnailUrl,
              channel: channel,
              url: canonicalUrl,
              platform: platform,
              videoId: videoId,
            );
          }
        } finally {
          client.close(force: true);
        }
      } catch (_) {}
    }

    if (videoId.isNotEmpty || platform == 'Rumble') {
      return ResolvedLink(
        title: url,
        thumbnailUrl: thumbnailUrl,
        channel: platform,
        url: canonicalUrl,
        platform: platform,
        videoId: videoId,
      );
    }

    return ResolvedLink(
      title: url,
      thumbnailUrl: '',
      channel: '',
      url: url,
      platform: 'Web',
      videoId: '',
    );
  }
}
