import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/palettes.dart';
import '../../data/models/models.dart';

String formatTime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Video thumbnail with a neutral placeholder.
class VideoArtwork extends StatelessWidget {
  const VideoArtwork({super.key, required this.video, this.size, this.radius = 6});

  final Video video;
  final Size? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Colors.grey.shade800,
      child: const Center(child: Icon(Icons.music_note, color: Colors.white38)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.fromSize(
        size: size,
        child: video.thumbnailUrl.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: video.thumbnailUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

/// Thin progress bar; tap or drag horizontally to seek.
class SeekStrip extends StatelessWidget {
  const SeekStrip({super.key, required this.progress, required this.onSeekFraction, this.height = 12});

  final double progress;
  final ValueChanged<double> onSeekFraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seek(double dx) {
          if (width > 0) onSeekFraction((dx / width).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seek(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
          child: SizedBox(
            height: height,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Stack(
                children: [
                  Container(height: 2, width: width, color: Colors.white10),
                  Container(height: 2, width: width * progress, color: PlayerColors.progress),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
