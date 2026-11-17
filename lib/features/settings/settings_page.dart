import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/config/app_info.dart';
import '../../core/config/platforms.dart';
import '../../core/theme/palettes.dart';
import '../../core/utils/log.dart';
import '../../data/repositories/settings_repository.dart';
import '../library/history_page.dart';
import '../share/data_transfer.dart';
import '../stats/stats_page.dart';
import 'faq_page.dart';
import 'in_app_browser_page.dart';
import 'toggles_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _privacyOptionsRequired = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrivacyOptionsStatus());
  }

  Future<void> _loadPrivacyOptionsStatus() async {
    try {
      final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      if (!mounted) return;
      setState(() => _privacyOptionsRequired = status == PrivacyOptionsRequirementStatus.required);
    } on Exception catch (e) {
      log('privacy options check failed: $e');
    }
  }

  void _update(AppSettings Function(AppSettings) change) =>
      unawaited(ref.read(settingsProvider.notifier).update(change));

  void _push(Widget page) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)));

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _clearCache() async {
    final ok = await _confirm(
      'Clear Cache',
      'This resets theme, accent color, hub background and platform choice to their defaults. Continue?',
      'Clear',
    );
    if (!ok) return;
    await ref.read(settingsProvider.notifier).resetAppearance();
    if (mounted) _snack('Cache cleared');
  }

  Future<void> _clearHistory() async {
    final ok = await _confirm(
      'Clear Watch History',
      'This will remove all watched videos from your history. This action cannot be undone.',
      'Clear',
    );
    if (!ok) return;
    await ref.read(historyRepositoryProvider).clear();
    if (mounted) _snack('History cleared');
  }

  Rect? _origin() {
    final box = context.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  }

  Future<void> _shareApp() async {
    try {
      await Share.share(
        'Check out MrPlay – your all-in-one video hub!\n${AppInfo.appStoreUrl}',
        sharePositionOrigin: _origin(),
      );
    } on Exception {
      if (mounted) _snack('Could not open the share sheet');
    }
  }

  Future<void> _launch(Uri uri, String failure) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack(failure);
    } on Exception {
      if (mounted) _snack(failure);
    }
  }

  void _email(String subject) => unawaited(
        _launch(
          Uri(scheme: 'mailto', path: AppInfo.supportEmail, queryParameters: {'subject': subject}),
          'Could not open your email app',
        ),
      );

  void _showAbout() => unawaited(
        showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Center(child: Text(AppInfo.name)),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppInfo.tagline, style: TextStyle(fontSize: 16)),
                SizedBox(height: 16),
                Text('Version ${AppInfo.version}'),
                SizedBox(height: 8),
                Text('©2026 sofien'),
                SizedBox(height: 8),
                Text('Made with love in Tunisia 🇹🇳'),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Dismiss'))],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Appearance'),
          _Tile(
            icon: Icons.brightness_auto,
            title: 'Theme Mode',
            subtitle: s.themeMode.name.toUpperCase(),
            onTap: () => _pickTheme(s.themeMode),
          ),
          _Tile(
            icon: Icons.palette_outlined,
            title: 'Accent Color',
            subtitle: 'Pick your highlight color',
            trailing: CircleAvatar(radius: 10, backgroundColor: s.accentColor),
            onTap: () => _pickAccent(s.accentColor),
          ),
          _Tile(
            icon: Icons.wallpaper_outlined,
            title: 'Hub Background',
            subtitle: HubBackgrounds.at(s.hubBackground).name,
            onTap: () => _pickBackground(s.hubBackground),
          ),
          const _Header('Manage Apps'),
          _Tile(
            icon: Icons.apps,
            title: 'Default Platform',
            subtitle: s.defaultPlatform,
            onTap: () => _pickPlatform(s.defaultPlatform),
          ),
          const _Header('Data'),
          _Tile(
            icon: Icons.bar_chart,
            title: 'Watch Stats',
            subtitle: 'Your watch time and usage',
            onTap: () => _push(const StatsPage()),
          ),
          _Tile(
            icon: Icons.history,
            title: 'View History',
            subtitle: 'Watch history records',
            onTap: () => _push(const HistoryPage()),
          ),
          _Tile(
            icon: Icons.file_upload_outlined,
            title: 'Export Data',
            subtitle: 'Save your library as a JSON file',
            onTap: () => unawaited(ref.read(dataTransferProvider).exportJson(context)),
          ),
          _Tile(
            icon: Icons.file_download_outlined,
            title: 'Import Data',
            subtitle: 'From a MrPlay .json or a .csv file',
            onTap: () => _snack('Share a .json or .csv file to MrPlay to import it'),
          ),
          _Tile(
            icon: Icons.delete_outline,
            title: 'Clear Cache',
            subtitle: 'Reset appearance settings to default',
            onTap: () => unawaited(_clearCache()),
          ),
          const _Header('About'),
          _Tile(
            icon: Icons.info_outline,
            title: AppInfo.name,
            subtitle: 'Version ${AppInfo.version}',
            onTap: _showAbout,
          ),
          _Tile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'How we handle your data',
            onTap: () => _push(
              const InAppBrowserPage(url: AppInfo.privacyPolicyUrl, title: 'Privacy Policy'),
            ),
          ),
          _Tile(
            icon: Icons.star_outline,
            title: 'Rate App',
            subtitle: 'Rate us on the App Store',
            onTap: () => unawaited(_launch(Uri.parse(AppInfo.appStoreUrl), 'Could not open the App Store')),
          ),
          _Tile(
            icon: Icons.share,
            title: 'Share App',
            subtitle: 'Tell your friends about MrPlay',
            onTap: () => unawaited(_shareApp()),
          ),
          _Tile(
            icon: Icons.quiz_outlined,
            title: 'FAQ',
            subtitle: 'Frequently asked questions',
            onTap: () => _push(const FaqPage()),
          ),
          const _Header('Privacy & Security'),
          if (_privacyOptionsRequired)
            _Tile(
              icon: Icons.ads_click,
              title: 'Ad Privacy Options',
              subtitle: 'Review your ad consent choices',
              onTap: () => unawaited(ConsentForm.showPrivacyOptionsForm((_) {})),
            ),
          _Tile(
            icon: Icons.toggle_on_outlined,
            title: 'Toggles',
            subtitle: 'Playback & content switches',
            onTap: () => _push(const TogglesPage()),
          ),
          _Tile(
            icon: Icons.delete_sweep_outlined,
            title: 'Clear History',
            subtitle: 'Clear watched videos record',
            onTap: () => unawaited(_clearHistory()),
          ),
          const _Header('Contact Us'),
          _Tile(
            icon: Icons.bug_report_outlined,
            title: 'Report a Bug',
            subtitle: 'Something not working? Tell us',
            onTap: () => _email('MrPlay - Bug Report'),
          ),
          _Tile(
            icon: Icons.lightbulb_outline,
            title: 'Suggest New Features',
            subtitle: 'Share your ideas with us',
            onTap: () => _email('MrPlay - Feature Suggestion'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- pickers

  void _sheet(Widget Function(BuildContext) builder) => unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (c) => SafeArea(child: builder(c)),
        ),
      );

  void _pickTheme(ThemeMode current) => _sheet(
        (c) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (mode, icon) in [
              (ThemeMode.light, Icons.brightness_5),
              (ThemeMode.dark, Icons.brightness_3),
              (ThemeMode.system, Icons.brightness_auto),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(mode.name[0].toUpperCase() + mode.name.substring(1)),
                trailing: mode == current ? const Icon(Icons.check) : null,
                onTap: () {
                  _update((s) => s.copyWith(themeMode: mode));
                  Navigator.pop(c);
                },
              ),
          ],
        ),
      );

  void _pickAccent(Color current) => _sheet(
        (c) => _PickerSheet(
          title: 'Accent Color',
          children: [
            for (final color in AccentColors.all)
              GestureDetector(
                onTap: () {
                  _update((s) => s.copyWith(accentColor: color));
                  Navigator.pop(c);
                },
                child: _Swatch(
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  selected: color.toARGB32() == current.toARGB32(),
                ),
              ),
          ],
        ),
      );

  void _pickBackground(int current) => _sheet(
        (c) => _PickerSheet(
          title: 'Hub Background',
          children: [
            for (var i = 0; i < HubBackgrounds.all.length; i++)
              GestureDetector(
                onTap: () {
                  _update((s) => s.copyWith(hubBackground: i));
                  Navigator.pop(c);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Swatch(
                      decoration: HubBackgrounds.decoration(i).copyWith(shape: BoxShape.circle),
                      selected: i == current,
                    ),
                    const SizedBox(height: 6),
                    Text(HubBackgrounds.all[i].name, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      );

  void _pickPlatform(String current) => _sheet(
        (c) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in Platforms.builtIn)
                ListTile(
                  leading: Icon(p.icon, color: p.color),
                  title: Text(p.name),
                  trailing: p.name == current ? const Icon(Icons.check) : null,
                  onTap: () {
                    _update((s) => s.copyWith(defaultPlatform: p.name));
                    Navigator.pop(c);
                  },
                ),
            ],
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
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

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Wrap(spacing: 16, runSpacing: 14, children: children),
          ],
        ),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.decoration, required this.selected});

  final BoxDecoration decoration;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: decoration.copyWith(
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected ? const Icon(Icons.check, color: Colors.white, size: 22) : null,
      );
}
