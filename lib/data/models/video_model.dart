import 'package:equatable/equatable.dart';

class VideoInfo extends Equatable {
  final bool isPlaying;
  final double currentTime;
  final double duration;
  final String title;
  final String channel;
  final String thumbnailUrl;

  const VideoInfo({
    this.isPlaying = false,
    this.currentTime = 0,
    this.duration = 0,
    this.title = '',
    this.channel = '',
    this.thumbnailUrl = '',
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      isPlaying: json['isPlaying'] == true,
      currentTime: (json['currentTime'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      title: json['title'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      thumbnailUrl: json['thumbnail'] as String? ?? '',
    );
  }

  VideoInfo copyWith({
    bool? isPlaying,
    double? currentTime,
    double? duration,
    String? title,
    String? channel,
    String? thumbnailUrl,
  }) {
    return VideoInfo(
      isPlaying: isPlaying ?? this.isPlaying,
      currentTime: currentTime ?? this.currentTime,
      duration: duration ?? this.duration,
      title: title ?? this.title,
      channel: channel ?? this.channel,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }

  @override
  List<Object?> get props => [isPlaying, currentTime, duration, title, channel, thumbnailUrl];
}
