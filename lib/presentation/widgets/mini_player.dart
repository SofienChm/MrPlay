import 'package:flutter/material.dart';
import '../../data/models/video_model.dart';
import 'favorite_button.dart';

class MiniPlayerWidget extends StatelessWidget {
  final VideoInfo video;
  final VoidCallback onMaximize;
  final VoidCallback onClose;
  final VoidCallback? onPlayPause;

  const MiniPlayerWidget({
    super.key,
    required this.video,
    required this.onMaximize,
    required this.onClose,
    this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onMaximize,
      child: Container(
        height: 70,
        color: Colors.black87,
        child: Row(
          children: [
            Container(
              width: 120,
              color: Colors.grey,
              child: video.thumbnailUrl.isNotEmpty
                  ? Image.network(video.thumbnailUrl, fit: BoxFit.cover)
                  : const Icon(Icons.play_circle, color: Colors.white54, size: 40),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      video.channel,
                      maxLines: 1,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            FavoriteButton(
              id: '${video.title}-${video.channel}',
              title: video.title,
              channel: video.channel,
              thumbnailUrl: video.thumbnailUrl,
              platformUrl: '',
            ),
            IconButton(
              icon: Icon(
                video.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: onPlayPause,
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
