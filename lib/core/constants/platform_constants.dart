import '../theme/app_colors.dart';
import '../../data/models/platform_model.dart';

class PlatformConstants {
  static final List<PlatformModel> platforms = [
    PlatformModel(name: 'YouTube', url: 'https://m.youtube.com', icon: 'youtube', category: 'video', subtitle: 'Optimized', color: AppColors.youtube),
    PlatformModel(name: 'YouTube Music', url: 'https://music.youtube.com', icon: 'youtube_music', category: 'music', subtitle: 'Optimized', color: AppColors.music),
    PlatformModel(name: 'Kick', url: 'https://kick.com', icon: 'kick', category: 'video', subtitle: 'Browser', color: AppColors.kick),
    PlatformModel(name: 'DailyMotion', url: 'https://www.dailymotion.com', icon: 'dailymotion', category: 'video', subtitle: 'Browser', color: AppColors.dailymotion),
    PlatformModel(name: 'Twitch', url: 'https://m.twitch.tv', icon: 'twitch', category: 'video', subtitle: 'Browser', color: AppColors.twitch),
  ];
}
