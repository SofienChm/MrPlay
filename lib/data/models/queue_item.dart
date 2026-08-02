import 'package:hive/hive.dart';

/// A video queued for playback from any platform.
class QueueItem extends HiveObject {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String platformUrl;
  final String platformName;
  final int sortIndex;

  QueueItem({
    required this.id,
    required this.title,
    this.thumbnailUrl = '',
    required this.platformUrl,
    required this.platformName,
    this.sortIndex = 0,
  });

  QueueItem copyWith({int? sortIndex}) {
    return QueueItem(
      id: id,
      title: title,
      thumbnailUrl: thumbnailUrl,
      platformUrl: platformUrl,
      platformName: platformName,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }
}

/// Hand-written adapter (avoids a build_runner step for a 6-field model).
class QueueItemAdapter extends TypeAdapter<QueueItem> {
  @override
  final int typeId = 2;

  @override
  QueueItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QueueItem(
      id: fields[0] as String,
      title: fields[1] as String,
      thumbnailUrl: fields[2] as String? ?? '',
      platformUrl: fields[3] as String,
      platformName: fields[4] as String? ?? '',
      sortIndex: fields[5] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, QueueItem obj) {
    writer
      ..writeByte(6)
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
      ..write(obj.sortIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
