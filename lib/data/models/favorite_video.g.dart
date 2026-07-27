// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_video.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FavoriteVideoAdapter extends TypeAdapter<FavoriteVideo> {
  @override
  final int typeId = 0;

  @override
  FavoriteVideo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FavoriteVideo(
      id: fields[0] as String,
      title: fields[1] as String,
      channel: fields[2] as String,
      thumbnailUrl: fields[3] as String,
      platformUrl: fields[4] as String,
      addedAt: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, FavoriteVideo obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.channel)
      ..writeByte(3)
      ..write(obj.thumbnailUrl)
      ..writeByte(4)
      ..write(obj.platformUrl)
      ..writeByte(5)
      ..write(obj.addedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteVideoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
