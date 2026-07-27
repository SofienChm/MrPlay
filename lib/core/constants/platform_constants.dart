import '../theme/app_colors.dart';
import '../../data/models/platform_model.dart';

class PlatformConstants {
  static final List<PlatformModel> platforms = [
    PlatformModel(name: 'YouTube', url: 'https://m.youtube.com', icon: 'youtube', category: 'video', color: AppColors.youtube),
    PlatformModel(name: 'Music', url: 'https://music.youtube.com', icon: 'music', category: 'music', color: AppColors.music),
    PlatformModel(name: 'Twitch', url: 'https://m.twitch.tv', icon: 'twitch', category: 'video', color: AppColors.twitch),
    PlatformModel(name: 'Rumble', url: 'https://rumble.com', icon: 'rumble', category: 'video', color: AppColors.rumble),
    PlatformModel(name: 'Duolingo', url: 'https://duolingo.com', icon: 'duolingo', category: 'education', color: AppColors.duolingo),
    PlatformModel(name: 'Busuu', url: 'https://busuu.com', icon: 'busuu', category: 'education', color: AppColors.busuu),
    PlatformModel(name: 'Babbel', url: 'https://babbel.com', icon: 'babbel', category: 'education', color: AppColors.babbel),
    PlatformModel(name: 'Memrise', url: 'https://memrise.com', icon: 'memrise', category: 'education', color: AppColors.memrise),
    PlatformModel(name: 'Mondly', url: 'https://mondly.com', icon: 'mondly', category: 'education', color: AppColors.mondly),
    PlatformModel(name: 'Instagram', url: 'https://instagram.com', icon: 'instagram', category: 'social', color: AppColors.instagram),
    PlatformModel(name: 'Reddit', url: 'https://reddit.com', icon: 'reddit', category: 'social', color: AppColors.reddit),
    PlatformModel(name: 'Facebook', url: 'https://facebook.com', icon: 'facebook', category: 'social', color: AppColors.facebook),
    PlatformModel(name: 'X', url: 'https://x.com', icon: 'x', category: 'social', color: AppColors.x),
    PlatformModel(name: 'Disney+', url: 'https://disneyplus.com', icon: 'disney', category: 'streaming', color: AppColors.disney),
    PlatformModel(name: 'HBO Max', url: 'https://max.com', icon: 'hbo', category: 'streaming', color: AppColors.hbo),
    PlatformModel(name: 'Prime Video', url: 'https://primevideo.com', icon: 'prime', category: 'streaming', color: AppColors.prime),
    PlatformModel(name: 'Pinterest', url: 'https://pinterest.com', icon: 'pinterest', category: 'social', color: AppColors.pinterest),
    PlatformModel(name: 'Quora', url: 'https://quora.com', icon: 'quora', category: 'social', color: AppColors.quora),
    PlatformModel(name: '9gag', url: 'https://9gag.com', icon: '9gag', category: 'social', color: AppColors.gag),
    PlatformModel(name: 'iFunny', url: 'https://ifunny.co', icon: 'ifunny', category: 'social', color: AppColors.ifunny),
  ];
}
