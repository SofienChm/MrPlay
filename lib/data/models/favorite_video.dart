import 'package:hive/hive.dart';

part 'favorite_video.g.dart';

@HiveType(typeId: 0)
class FavoriteVideo extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String channel;

  @HiveField(3)
  final String thumbnailUrl;

  @HiveField(4)
  final String platformUrl;

  @HiveField(5)
  final DateTime addedAt;

  FavoriteVideo({
    required this.id,
    required this.title,
    required this.channel,
    required this.thumbnailUrl,
    required this.platformUrl,
    required this.addedAt,
  });
}
