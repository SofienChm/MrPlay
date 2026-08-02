import 'package:hive/hive.dart';

/// User-added platform shortcut shown in the hub grid.
class CustomBookmark extends HiveObject {
  final String id;
  final String name;
  final String url;
  final DateTime addedAt;

  CustomBookmark({
    required this.id,
    required this.name,
    required this.url,
    required this.addedAt,
  });
}

/// Hand-written adapter (avoids a build_runner step for a 4-field model).
class CustomBookmarkAdapter extends TypeAdapter<CustomBookmark> {
  @override
  final int typeId = 1;

  @override
  CustomBookmark read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CustomBookmark(
      id: fields[0] as String,
      name: fields[1] as String,
      url: fields[2] as String,
      addedAt: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, CustomBookmark obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.url)
      ..writeByte(3)
      ..write(obj.addedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomBookmarkAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
