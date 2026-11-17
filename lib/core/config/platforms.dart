import 'package:flutter/material.dart';

/// A site shown as a tile on the hub (built-in or user shortcut).
@immutable
class Platform {
  const Platform({
    required this.name,
    required this.url,
    required this.icon,
    required this.color,
    this.isCustom = false,
  });

  final String name;
  final String url;
  final IconData icon;
  final Color color;
  final bool isCustom;
}

abstract final class Platforms {
  static const String defaultName = 'YouTube';

  static const List<Platform> builtIn = [
    Platform(name: 'YouTube', url: 'https://m.youtube.com', icon: Icons.play_circle_filled, color: Color(0xFFFF0000)),
    Platform(name: 'Music', url: 'https://music.youtube.com', icon: Icons.music_note, color: Color(0xFFFF0000)),
    Platform(name: 'DailyMotion', url: 'https://www.dailymotion.com', icon: Icons.videocam, color: Color(0xFF0066DC)),
    Platform(name: 'Twitch', url: 'https://m.twitch.tv', icon: Icons.live_tv, color: Color(0xFF9146FF)),
    Platform(name: 'Kick', url: 'https://kick.com', icon: Icons.bolt, color: Color(0xFF53FC18)),
    Platform(name: '9Gag', url: 'https://9gag.com', icon: Icons.emoji_emotions, color: Color(0xFF00CC00)),
    Platform(name: 'iFunny', url: 'https://ifunny.co', icon: Icons.sentiment_very_satisfied, color: Color(0xFF2FB5E8)),
    Platform(name: 'Rumble', url: 'https://rumble.com', icon: Icons.video_library, color: Color(0xFF85C742)),
  ];

  static Platform? byName(String name) {
    for (final p in builtIn) {
      if (p.name.toLowerCase() == name.toLowerCase()) return p;
    }
    return null;
  }

  static IconData iconFor(String platformName) =>
      byName(platformName)?.icon ?? Icons.public;
}
