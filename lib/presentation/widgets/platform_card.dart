import 'package:flutter/material.dart';
import '../../data/models/platform_model.dart';

class PlatformCard extends StatefulWidget {
  final PlatformModel platform;
  final VoidCallback onTap;

  const PlatformCard({
    super.key,
    required this.platform,
    required this.onTap,
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
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
      case 'youtube': return Icons.play_circle_filled;
      case 'music': return Icons.music_note;
      case 'twitch': return Icons.live_tv;
      case 'rumble': return Icons.video_library;
      case 'duolingo': return Icons.school;
      case 'busuu': return Icons.language;
      case 'babbel': return Icons.translate;
      case 'memrise': return Icons.psychology;
      case 'mondly': return Icons.record_voice_over;
      case 'instagram': return Icons.camera_alt;
      case 'reddit': return Icons.forum;
      case 'facebook': return Icons.facebook;
      case 'x': return Icons.close_fullscreen;
      case 'disney': return Icons.movie;
      case 'hbo': return Icons.tv;
      case 'prime': return Icons.play_circle;
      case 'pinterest': return Icons.push_pin;
      case 'quora': return Icons.help_outline;
      case '9gag': return Icons.emoji_emotions;
      case 'ifunny': return Icons.sentiment_very_satisfied;
      default: return Icons.open_in_browser;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
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
            color: widget.platform.color ?? Colors.grey,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (widget.platform.color ?? Colors.grey).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _getIconData(widget.platform.icon),
                size: 36,
                color: Colors.white,
              ),
              const SizedBox(height: 8),
              Text(
                widget.platform.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
