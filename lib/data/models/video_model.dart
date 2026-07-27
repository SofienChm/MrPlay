class VideoInfo {
  final bool isPlaying;
  final double currentTime;
  final double duration;
  final String title;
  final String channel;
  final String thumbnail;

  const VideoInfo({
    this.isPlaying = false,
    this.currentTime = 0,
    this.duration = 0,
    this.title = '',
    this.channel = '',
    this.thumbnail = '',
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      isPlaying: json['isPlaying'] ?? false,
      currentTime: (json['currentTime'] ?? 0).toDouble(),
      duration: (json['duration'] ?? 0).toDouble(),
      title: json['title'] ?? '',
      channel: json['channel'] ?? '',
      thumbnail: json['thumbnail'] ?? '',
    );
  }

  String get thumbnailUrl {
    if (thumbnail.isEmpty) return '';
    final match = RegExp(r'url\("?(.+?)"?\)').firstMatch(thumbnail);
    return match?.group(1) ?? thumbnail;
  }
}
