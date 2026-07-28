class Video {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String videoUrl;
  final String platform;

  const Video({
    required this.id,
    required this.title,
    this.thumbnailUrl = '',
    required this.videoUrl,
    this.platform = '',
  });
}
