import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app.dart';
import '../../core/constants/platform_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/hub_backgrounds.dart';
import '../../data/repositories/settings_repository.dart';
import '../../services/recent_activity_service.dart';
import 'stats_page.dart';
import 'history_page.dart';
import 'toggles_page.dart';
import 'faq_page.dart';
import 'in_app_browser_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _themeMode = 'system';
  String _defaultPlatform = 'YouTube';
  int _accent = SettingsRepository.defaultAccentColor;
  int _hubBackground = 0;
  bool _disposed = false;

  static const List<Color> _accentChoices = [
    Color(0xFF2196F3),
    Color(0xFF3F51B5),
    Color(0xFF9C27B0),
    Color(0xFFE91E63),
    Color(0xFFF44336),
    Color(0xFFFF9800),
    Color(0xFF4CAF50),
    Color(0xFF009688),
  ];

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
    final accent = await SettingsRepository.getAccentColor();
    final hubBackground = await SettingsRepository.getHubBackground();
    if (_disposed || !mounted) return;
    setState(() {
      _themeMode = theme;
      _defaultPlatform = platform;
      _accent = accent;
      _hubBackground = hubBackground;
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

  Future<void> _changeAccent(Color color) async {
    await SettingsRepository.setAccentColor(color.toARGB32());
    setState(() => _accent = color.toARGB32());
    MrPlayApp.accentColorNotifier.value = color;
  }

  Future<void> _changeHubBackground(int index) async {
    await SettingsRepository.setHubBackground(index);
    setState(() => _hubBackground = index);
    MrPlayApp.hubBackgroundNotifier.value = index;
  }

  Future<void> _clearCache() async {
    await SettingsRepository.clearCache();
    setState(() {
      _themeMode = 'system';
      _defaultPlatform = 'YouTube';
      _accent = SettingsRepository.defaultAccentColor;
      _hubBackground = 0;
    });
    MrPlayApp.themeModeNotifier.value = ThemeMode.system;
    MrPlayApp.accentColorNotifier.value =
        const Color(SettingsRepository.defaultAccentColor);
    MrPlayApp.hubBackgroundNotifier.value = 0;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared')),
      );
    }
  }

  void _confirmClearCache() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
            'This resets all settings (theme, accent color, hub background, platform choice) to their defaults. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearCache();
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearHistory() async {
    await RecentActivityService.instance.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('History cleared')),
      );
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
          _SettingsTile(
            icon: Icons.palette_outlined,
            title: 'Accent Color',
            subtitle: 'Pick your highlight color',
            trailing: CircleAvatar(
              radius: 10,
              backgroundColor: Color(_accent),
            ),
            onTap: () => _showAccentPicker(),
          ),
          _SettingsTile(
            icon: Icons.wallpaper_outlined,
            title: 'Hub Background',
            subtitle: HubBackgrounds.names[_hubBackground.clamp(
                0, HubBackgrounds.palettes.length - 1)],
            onTap: () => _showHubBackgroundPicker(),
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
            onTap: _confirmClearCache,
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
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const InAppBrowserPage(
                  url: 'https://mrplay.app-miniminds.com/',
                  title: 'Privacy Policy',
                ),
              ),
            ),
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
            subtitle: AppConstants.isOnAppStore
                ? 'Rate us on the App Store'
                : 'Coming soon to the App Store',
            onTap: _rateApp,
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
    const text = 'Check out MrPlay – your all-in-one video hub!';
    final link =
        AppConstants.isOnAppStore ? ' ${AppConstants.appStoreUrl}' : '';
    try {
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        '$text$link',
        sharePositionOrigin:
            box != null && box.hasSize && box.size.width > 0
                ? box.localToGlobal(Offset.zero) & box.size
                : null,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the share sheet')),
        );
      }
    }
  }

  Future<void> _rateApp() async {
    if (!AppConstants.isOnAppStore) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MrPlay is coming soon to the App Store')),
      );
      return;
    }
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

  void _showHubBackgroundPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Hub Background',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 14,
                children: [
                  for (var i = 0; i < HubBackgrounds.palettes.length; i++)
                    GestureDetector(
                      onTap: () {
                        _changeHubBackground(i);
                        Navigator.pop(context);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: HubBackgrounds.palettes[i],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _hubBackground == i
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            HubBackgrounds.names[i],
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccentPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Accent Color',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: _accentChoices.map((color) {
                  final selected = color.toARGB32() == _accent;
                  return GestureDetector(
                    onTap: () {
                      _changeAccent(color);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 22)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
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
