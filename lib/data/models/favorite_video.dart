import 'package:equatable/equatable.dart';

class FavoriteVideo extends Equatable {
  final String id;
  final String title;
  final String channel;
  final String thumbnailUrl;
  final String platformUrl;
  final DateTime addedAt;

  FavoriteVideo({
    required this.id,
    required this.title,
    this.channel = '',
    this.thumbnailUrl = '',
    required this.platformUrl,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'channel': channel,
      'thumbnailUrl': thumbnailUrl,
      'platformUrl': platformUrl,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory FavoriteVideo.fromJson(Map<String, dynamic> json) {
    return FavoriteVideo(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      platformUrl: json['platformUrl'] as String? ?? '',
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? ''),
    );
  }

  @override
  List<Object?> get props => [id, title, channel, platformUrl];
}
