import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app.dart';
import '../../core/constants/platform_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../data/repositories/settings_repository.dart';
import '../../services/recent_activity_service.dart';
import 'stats_page.dart';
import 'history_page.dart';
import 'toggles_page.dart';
import 'faq_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _themeMode = 'system';
  String _defaultPlatform = 'YouTube';
  bool _historyEnabled = true;
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
    final history = await SettingsRepository.getHistoryEnabled();
    if (_disposed || !mounted) return;
    setState(() {
      _themeMode = theme;
      _defaultPlatform = platform;
      _historyEnabled = history;
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

  Future<void> _changeHistory(bool enabled) async {
    await SettingsRepository.setHistoryEnabled(enabled);
    setState(() => _historyEnabled = enabled);
  }

  Future<void> _clearCache() async {
    await SettingsRepository.clearCache();
    setState(() {
      _themeMode = 'system';
      _defaultPlatform = 'YouTube';
      _historyEnabled = true;
    });
    MrPlayApp.themeModeNotifier.value = ThemeMode.system;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared')),
      );
    }
  }

  Future<void> _clearHistory() async {
    await RecentActivityService.instance.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('History cleared')),
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
          const _SectionHeader(title: 'Manage Apps'),
          _SettingsTile(
            icon: Icons.apps,
            title: 'Choose Platforms',
            subtitle: 'Select which platforms appear in your hub',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPlatformPicker(),
          ),
          const _SectionHeader(title: 'Data'),
          _SettingsTile(
            icon: Icons.bar_chart,
            title: 'Watch Stats',
            subtitle: 'Your watch time and usage',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StatsPage()),
            ),
          ),
          _SettingsTile(
            icon: Icons.delete_outline,
            title: 'Clear Cache',
            subtitle: 'Reset all settings to default',
            onTap: _clearCache,
          ),
          _SettingsTile(
            icon: Icons.history,
            title: 'View History',
            subtitle: 'Watch history records',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => HistoryPage()),
            ),
          ),
          _SectionHeader(
            title: 'About',
          ),
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
            icon: Icons.info_outline,
            title: 'About MrPlay',
            subtitle: 'Learn more about the app',
            onTap: () => _showAboutMrPlayDialog(),
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
          _SettingsTile(
            icon: Icons.quiz_outlined,
            title: 'FAQ',
            subtitle: 'Frequently asked questions',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FaqPage()),
            ),
          ),
          const _SectionHeader(title: 'Privacy & Security'),
          _SettingsTile(
            icon: Icons.toggle_on_outlined,
            title: 'Toggles',
            subtitle: 'Playback & content switches',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TogglesPage()),
            ),
          ),
          _SettingsTile(
            icon: Icons.history,
            title: 'Enable Watch History',
            subtitle: _historyEnabled ? 'On' : 'Off',
            trailing: Switch(
              value: _historyEnabled,
              onChanged: (value) => _changeHistory(value),
            ),
          ),
          _SettingsTile(
            icon: Icons.delete_outline,
            title: 'Clear History',
            subtitle: 'Clear watched videos record',
            onTap: () => _showClearHistoryDialog(),
          ),
          const _SectionHeader(title: 'Contact Us'),
          _SettingsTile(
            icon: Icons.bug_report_outlined,
            title: 'Report a Bug',
            subtitle: 'Something not working? Tell us',
            onTap: () => _sendEmail('MrPlay - Bug Report'),
          ),
          _SettingsTile(
            icon: Icons.lightbulb_outline,
            title: 'Suggest New Features',
            subtitle: 'Share your ideas with us',
            onTap: () => _sendEmail('MrPlay - Feature Suggestion'),
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

  Future<void> _sendEmail(String subject) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'mrplayapp@gmail.com',
      queryParameters: {'subject': subject},
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open your email app')),
        );
      }
    }
  }

  void _showAboutMrPlayDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Center(child: Text('Mrplay')),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your all-in-one video hub',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text('Version ${AppConstants.appVersion}'),
            SizedBox(height: 8),
            Text('©2026 sofien'),
            SizedBox(height: 8),
            Text('Made with love in Tunisia 🇹🇳'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Watch History'),
        content: const Text('This will remove all watched videos from your history. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _clearHistory();
              Navigator.pop(context);
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
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
        initialChildSize: 0.7,
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
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
