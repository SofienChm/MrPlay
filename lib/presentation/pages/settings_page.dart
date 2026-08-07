import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app.dart';
import '../../core/constants/platform_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../data/repositories/settings_repository.dart';
import 'stats_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _themeMode = 'system';
  String _defaultPlatform = 'YouTube';
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final theme = await SettingsRepository.getThemeMode();
    final platform = await SettingsRepository.getDefaultPlatform();
    if (_disposed || !mounted) return;
    setState(() {
      _themeMode = theme;
      _defaultPlatform = platform;
    });
  }

  ThemeMode get _currentThemeMode {
    switch (_themeMode) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  Future<void> _changeTheme(String mode) async {
    await SettingsRepository.setThemeMode(mode);
    setState(() => _themeMode = mode);
    MrPlayApp.themeModeNotifier.value = _currentThemeMode;
  }

  Future<void> _changeDefaultPlatform(String name) async {
    await SettingsRepository.setDefaultPlatform(name);
    setState(() => _defaultPlatform = name);
  }

  Future<void> _clearCache() async {
    await SettingsRepository.clearCache();
    setState(() {
      _themeMode = 'system';
      _defaultPlatform = 'YouTube';
    });
    MrPlayApp.themeModeNotifier.value = ThemeMode.system;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared')),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Appearance'),
          _SettingsTile(
            icon: Icons.brightness_auto,
            title: 'Theme Mode',
            subtitle: _themeMode.toUpperCase(),
            onTap: () => _showThemePicker(),
          ),
          const _SectionHeader(title: 'Platforms'),
          _SettingsTile(
            icon: Icons.home,
            title: 'Default Platform',
            subtitle: _defaultPlatform,
            onTap: () => _showPlatformPicker(),
          ),
          const _SectionHeader(title: 'Data'),
          _SettingsTile(
            icon: Icons.bar_chart,
            title: 'Watch Stats',
            subtitle: 'Your watch time and usage',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StatsPage()),
            ),
          ),
          _SettingsTile(
            icon: Icons.delete_outline,
            title: 'Clear Cache',
            subtitle: 'Reset all settings to default',
            onTap: _clearCache,
          ),
          const _SectionHeader(title: 'About'),
          _SettingsTile(
            icon: Icons.info_outline,
            title: AppConstants.appName,
            subtitle: 'Version ${AppConstants.appVersion}',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'How we handle your data',
            onTap: () => _openUrl('https://mrplay.app-miniminds.com/'),
          ),
          _SettingsTile(
            icon: Icons.star_outline,
            title: 'Rate App',
            subtitle: 'Rate us on the App Store',
            onTap: () => _openUrl(AppConstants.appStoreUrl),
          ),
          _SettingsTile(
            icon: Icons.share,
            title: 'Share App',
            subtitle: 'Tell your friends about MrPlay',
            onTap: () => _shareApp(),
          ),
        ],
      ),
    );
  }

  Future<void> _shareApp() async {
    final uri = Uri.parse(AppConstants.appStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.brightness_5),
              title: const Text('Light'),
              trailing: _themeMode == 'light' ? const Icon(Icons.check, color: Colors.blue) : null,
              onTap: () { _changeTheme('light'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.brightness_3),
              title: const Text('Dark'),
              trailing: _themeMode == 'dark' ? const Icon(Icons.check, color: Colors.blue) : null,
              onTap: () { _changeTheme('dark'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.brightness_auto),
              title: const Text('System'),
              trailing: _themeMode == 'system' ? const Icon(Icons.check, color: Colors.blue) : null,
              onTap: () { _changeTheme('system'); Navigator.pop(context); },
            ),
          ],
        ),
      ),
    );
  }

  void _showPlatformPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) => ListView.builder(
          controller: scrollController,
          itemCount: PlatformConstants.platforms.length,
          itemBuilder: (context, index) {
            final platform = PlatformConstants.platforms[index];
            return ListTile(
              leading: Icon(Icons.open_in_browser, color: platform.color),
              title: Text(platform.name),
              trailing: _defaultPlatform == platform.name
                  ? const Icon(Icons.check, color: Colors.blue)
                  : null,
              onTap: () {
                _changeDefaultPlatform(platform.name);
                Navigator.pop(context);
              },
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
