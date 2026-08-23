import 'package:hive/hive.dart';

/// A user-created playlist (e.g. "Gym", "Study"). Its entries live in a
/// separate `playlist_items` box (see [PlaylistItem]).
class Playlist extends HiveObject {
  final String id;
  final String name;
  final DateTime addedAt;

  Playlist({
    required this.id,
    required this.name,
    required this.addedAt,
  });
}

/// Hand-written adapter (avoids a build_runner step for a 3-field model).
class PlaylistAdapter extends TypeAdapter<Playlist> {
  @override
  final int typeId = 3;

  @override
  Playlist read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Playlist(
      id: fields[0] as String,
      name: fields[1] as String,
      addedAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Playlist obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.addedAt);
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
