import 'package:hive/hive.dart';

/// A saved item inside a [Playlist] (a video or music track, from any
/// platform including YouTube and YouTube Music).
class PlaylistItem {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String platformUrl;
  final String platformName;
  final DateTime addedAt;
  final int sortIndex;

  PlaylistItem({
    required this.id,
    required this.title,
    this.thumbnailUrl = '',
    required this.platformUrl,
    required this.platformName,
    DateTime? addedAt,
    this.sortIndex = 0,
  }) : addedAt = addedAt ?? DateTime.now();

  PlaylistItem copyWith({int? sortIndex}) {
    return PlaylistItem(
      id: id,
      title: title,
      thumbnailUrl: thumbnailUrl,
      platformUrl: platformUrl,
      platformName: platformName,
      addedAt: addedAt,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }
}

/// User-created playlist displayed on the hub and filled from the player's
/// "Add to playlist" action.
class Playlist {
  final String id;
  final String name;
  final List<PlaylistItem> items;
  final DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    List<PlaylistItem>? items,
    DateTime? createdAt,
  })  : items = items ?? [],
        createdAt = createdAt ?? DateTime.now();
}

/// Hand-written adapter (avoids a build_runner step).
class PlaylistItemAdapter extends TypeAdapter<PlaylistItem> {
  @override
  final int typeId = 3;

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
      addedAt: fields[5] as DateTime? ?? DateTime.now(),
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
      ..write(obj.addedAt)
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

/// Hand-written adapter for [Playlist].
class PlaylistAdapter extends TypeAdapter<Playlist> {
  @override
  final int typeId = 4;

  @override
  Playlist read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Playlist(
      id: fields[0] as String,
      name: fields[1] as String,
      items: (fields[2] as List? ?? []).cast<PlaylistItem>(),
      createdAt: fields[3] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, Playlist obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.items)
      ..writeByte(3)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}