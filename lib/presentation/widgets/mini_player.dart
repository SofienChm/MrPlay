import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/constants/youtube_js.dart';
import '../../data/models/video_model.dart';

class MiniPlayerWidget extends StatelessWidget {
  final VideoInfo video;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final WebViewController controller;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  const MiniPlayerWidget({
    super.key,
    required this.video,
    required this.onTap,
    required this.onClose,
    required this.controller,
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: Colors.black87,
          border: Border(
            top: BorderSide(
              color: Colors.grey.shade800,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 120,
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.all(8),
              child: video.thumbnailUrl.isNotEmpty
                  ? Image.network(
                      video.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.movie, color: Colors.grey),
                    )
                  : const Icon(Icons.movie, color: Colors.grey),
            ),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    video.title.isNotEmpty ? video.title : 'No video playing',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    video.channel.isNotEmpty ? video.channel : 'Unknown',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Seek bar
                  if (video.duration > 0)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: video.duration > 0
                            ? video.currentTime / video.duration
                            : 0,
                        backgroundColor: Colors.grey.shade800,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF00C853),
                        ),
                        minHeight: 2,
                      ),
                    ),
                ],
              ),
            ),
            // Favorite toggle
            if (video.title.isNotEmpty)
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? Colors.red : Colors.white54,
                  size: 20,
                ),
                onPressed: onToggleFavorite,
                tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
              ),
            // Play/Pause
            IconButton(
              icon: Icon(
                video.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: () {
                controller.runJavaScript(
                  video.isPlaying ? YouTubeJS.pauseScript : YouTubeJS.playScript,
                );
              },
              tooltip: video.isPlaying ? 'Pause' : 'Play',
            ),
            // Close
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: onClose,
              tooltip: 'Close',
            ),
          ],
        ),
      ),
    );
  }
}
