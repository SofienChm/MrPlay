import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import 'browser_screen.dart';
import '../widgets/unified_banner_ad_slot.dart';

class PlatformItem {
  final String name;
  final String url;
  final IconData icon;
  final Color color;

  const PlatformItem({
    required this.name,
    required this.url,
    required this.icon,
    required this.color,
  });
}

const List<PlatformItem> _platforms = [
  PlatformItem(
    name: 'YouTube',
    url: 'https://m.youtube.com',
    icon: Icons.play_circle_fill,
    color: Colors.red,
  ),
  PlatformItem(
    name: 'Google',
    url: 'https://www.google.com',
    icon: Icons.search,
    color: Colors.blue,
  ),
  PlatformItem(
    name: 'Twitch',
    url: 'https://m.twitch.tv',
    icon: Icons.video_library,
    color: Colors.purple,
  ),
  PlatformItem(
    name: 'Kick',
    url: 'https://kick.com',
    icon: Icons.live_tv,
    color: Colors.green,
  ),
  PlatformItem(
    name: 'X',
    url: 'https://x.com',
    icon: Icons.tag,
    color: Colors.white,
  ),
  PlatformItem(
    name: 'Pinterest',
    url: 'https://www.pinterest.com',
    icon: Icons.photo_library,
    color: Colors.redAccent,
  ),
  PlatformItem(
    name: 'DuckDuckGo',
    url: 'https://duckduckgo.com',
    icon: Icons.security,
    color: Colors.orange,
  ),
];

class LauncherHubScreen extends StatelessWidget {
  final ValueChanged<String>? onOpenBrowser;

  const LauncherHubScreen({super.key, this.onOpenBrowser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hub',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select a platform',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withAlpha(128),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _platforms.length,
                  itemBuilder: (context, index) {
                    final item = _platforms[index];
                    return _PlatformTile(
                      item: item,
                      onOpenBrowser: onOpenBrowser,
                    );
                  },
                ),
              ),
              const Divider(
                color: AppColors.border,
                height: 24,
                thickness: 1,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  'Ad',
                  style: TextStyle(
                    color: Colors.white.withAlpha(77),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: UnifiedBannerAdSlot(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformTile extends StatelessWidget {
  final PlatformItem item;
  final ValueChanged<String>? onOpenBrowser;

  const _PlatformTile({required this.item, this.onOpenBrowser});

  Future<void> _handleTap(BuildContext context) async {
    if (item.name == 'YouTube') {
      final prefs = await SharedPreferences.getInstance();
      final hasAsked = prefs.containsKey('asked_default_preference');

      if (!hasAsked) {
        if (!context.mounted) return;
        final choice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceLight,
            title: const Text(
              'Set as Default?',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            content: const Text(
              'Would you like this app to open YouTube directly every time you launch?',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('No', style: TextStyle(color: AppColors.textTertiary)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Yes', style: TextStyle(color: AppColors.accent)),
              ),
            ],
          ),
        );
        await prefs.setBool('auto_launch_youtube', choice ?? false);
        await prefs.setBool('asked_default_preference', true);
      }
    }

    if (!context.mounted) return;

    if (onOpenBrowser != null) {
      onOpenBrowser!(item.url);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BrowserScreen(targetUrl: item.url)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withAlpha(13),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _handleTap(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, color: item.color, size: 36),
              const SizedBox(height: 10),
              Text(
                item.name,
                style: TextStyle(
                  color: Colors.white.withAlpha(204),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
