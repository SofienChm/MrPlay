import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/platform_model.dart';

class PlatformCard extends StatefulWidget {
  final PlatformModel platform;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const PlatformCard({
    super.key,
    required this.platform,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<PlatformCard> createState() => _PlatformCardState();
}

class _PlatformCardState extends State<PlatformCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'youtube':
        return Icons.play_circle_filled;
      case 'youtube_music':
      case 'music':
        return Icons.music_note;
      case 'twitch':
        return Icons.live_tv;
      case 'kick':
        return Icons.sports_esports;
      case 'rumble':
        return Icons.video_library;
      case 'dailymotion':
        return Icons.ondemand_video;
      case 'vimeo':
        return Icons.videocam;
      case 'duolingo':
        return Icons.school;
      case 'busuu':
        return Icons.language;
      case 'babbel':
        return Icons.translate;
      case 'memrise':
        return Icons.psychology;
      case 'mondly':
        return Icons.record_voice_over;
      case 'instagram':
        return Icons.camera_alt;
      case 'reddit':
        return Icons.forum;
      case 'facebook':
        return Icons.facebook;
      case 'x':
        return Icons.close_fullscreen;
      case 'disney':
        return Icons.movie;
      case 'hbo':
        return Icons.tv;
      case 'prime':
        return Icons.play_circle;
      case 'pinterest':
        return Icons.push_pin;
      case 'quora':
        return Icons.help_outline;
      case '9gag':
        return Icons.emoji_emotions;
      case 'ifunny':
        return Icons.sentiment_very_satisfied;
      case 'custom':
        return Icons.public;
      default:
        return Icons.open_in_browser;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.platform.color is Color
        ? widget.platform.color as Color
        : Colors.white70;
    final subtitle = widget.platform.subtitle;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.platform.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              const Spacer(),
              Align(
                alignment: Alignment.bottomRight,
                child: Icon(
                  _getIconData(widget.platform.icon),
                  size: 26,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
