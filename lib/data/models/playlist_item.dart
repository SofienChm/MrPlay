import 'package:hive/hive.dart';

/// A single entry in a [Playlist]. Its Hive key is a composite
/// `"$playlistId::$videoId"` so the same video can belong to multiple
/// playlists.
class PlaylistItem extends HiveObject {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String platformUrl;
  final String platformName;
  final String playlistId;
  final int sortIndex;

  PlaylistItem({
    required this.id,
    required this.title,
    this.thumbnailUrl = '',
    required this.platformUrl,
    required this.platformName,
    required this.playlistId,
    this.sortIndex = 0,
  });

  PlaylistItem copyWith({int? sortIndex}) {
    return PlaylistItem(
      id: id,
      title: title,
      thumbnailUrl: thumbnailUrl,
      platformUrl: platformUrl,
      platformName: platformName,
      playlistId: playlistId,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }
}

/// Hand-written adapter (avoids a build_runner step).
class PlaylistItemAdapter extends TypeAdapter<PlaylistItem> {
  @override
  final int typeId = 4;

  @override
  PlaylistItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlaylistItem(
      id: fields[0] as String,
      title: fields[1] as String,
      thumbnailUrl: fields[2] as String? ?? '',
      platformUrl: fields[3] as String,
      platformName: fields[4] as String? ?? '',
      playlistId: fields[5] as String? ?? '',
      sortIndex: fields[6] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, PlaylistItem obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.thumbnailUrl)
      ..writeByte(3)
      ..write(obj.platformUrl)
      ..writeByte(4)
      ..write(obj.platformName)
      ..writeByte(5)
      ..write(obj.playlistId)
      ..writeByte(6)
      ..write(obj.sortIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
