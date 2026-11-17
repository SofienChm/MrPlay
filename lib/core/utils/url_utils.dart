/// Pure URL helpers shared by the browser, player, link resolver and import.
abstract final class UrlUtils {
  static final RegExp _watchParam = RegExp(r'[?&]v=([^&#]+)');
  static final RegExp _shortLink = RegExp(r'youtu\.be/([^?&#/]+)');
  static final RegExp _twitchVideo = RegExp(r'twitch\.tv/videos/(\d+)');
  static final RegExp _twitchClip = RegExp(r'clips\.twitch\.tv/([a-zA-Z0-9_-]+)');
  static final RegExp _rumble = RegExp(r'rumble\.com/([a-zA-Z0-9_-]+)');

  /// YouTube video id from a watch or youtu.be URL.
  static String? youTubeId(String url) =>
      _watchParam.firstMatch(url)?.group(1) ?? _shortLink.firstMatch(url)?.group(1);

  /// Best-effort video id for any supported platform.
  static String? videoId(String url) =>
      youTubeId(url) ??
      _twitchVideo.firstMatch(url)?.group(1) ??
      _twitchClip.firstMatch(url)?.group(1) ??
      _rumble.firstMatch(url)?.group(1);

  static String youTubeThumbnail(String id) => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';

  static bool isYouTube(String url) => url.contains('youtube.com') || url.contains('youtu.be');

  static bool isMusic(String? url) => url != null && url.contains('music.youtube.com');

  /// Regular YouTube watch pages play in the dedicated video tab. YouTube Music
  /// keeps playing inline in the browser by design.
  static bool routesToVideoTab(String url) =>
      url.contains('/watch') && url.contains('youtube.com') && !isMusic(url);

  /// "m.dailymotion.com" -> "Dailymotion".
  static String platformName(String host) {
    var h = host;
    if (h.startsWith('m.')) {
      h = h.substring(2);
    } else if (h.startsWith('www.')) {
      h = h.substring(4);
    }
    final first = h.split('.').first;
    if (first.isEmpty) return 'Web';
    return '${first[0].toUpperCase()}${first.substring(1)}';
  }

  static String withScheme(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;
    return 'https://$trimmed';
  }

  static String googleSearch(String query) =>
      'https://www.google.com/search?q=${Uri.encodeComponent(query)}';

  /// Search URL for a platform's home URL.
  static String platformSearch(String baseUrl, String query) {
    final q = Uri.encodeComponent(query);
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    if (host.contains('music.youtube.com')) return 'https://music.youtube.com/search?q=$q';
    if (host.contains('youtube.com')) return 'https://m.youtube.com/results?search_query=$q';
    if (host.contains('twitch.tv')) return 'https://m.twitch.tv/search?term=$q';
    if (host.contains('dailymotion.com')) return 'https://www.dailymotion.com/search/$q';
    if (host.contains('kick.com')) return 'https://kick.com/search?query=$q';
    if (host.contains('rumble.com')) return 'https://rumble.com/search/all?q=$q';
    return '$baseUrl/search?q=$q';
  }
}
