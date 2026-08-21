import '../theme/app_colors.dart';
import '../../data/models/platform_model.dart';

class PlatformConstants {
  static final List<PlatformModel> platforms = [
    PlatformModel(name: 'YouTube', url: 'https://m.youtube.com', icon: 'youtube', category: 'video', color: AppColors.youtube),
    PlatformModel(name: 'Music', url: 'https://music.youtube.com', icon: 'music', category: 'music', color: AppColors.music),
    PlatformModel(name: 'DailyMotion', url: 'https://www.dailymotion.com', icon: 'dailymotion', category: 'video', color: AppColors.youtube),
    PlatformModel(name: 'Twitch', url: 'https://m.twitch.tv', icon: 'twitch', category: 'video', color: AppColors.twitch),
    PlatformModel(name: 'Kick', url: 'https://kick.com', icon: 'kick', category: 'video', color: AppColors.rumble),
    PlatformModel(name: '9Gag', url: 'https://9gag.com', icon: '9gag', category: 'social', color: AppColors.gag),
    PlatformModel(name: 'iFunny', url: 'https://ifunny.co', icon: 'ifunny', category: 'social', color: AppColors.ifunny),
    PlatformModel(name: 'Rumble', url: 'https://rumble.com', icon: 'rumble', category: 'video', color: AppColors.rumble),
  ];
}
