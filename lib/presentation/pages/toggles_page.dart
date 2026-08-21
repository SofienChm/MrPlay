import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';
import '../../services/remote_config_service.dart';

/// Privacy & Security → Toggles: hosts the two playback/privacy switches
/// ("Block ads & trackers" and "Background audio") on their own page.
class TogglesPage extends StatefulWidget {
  const TogglesPage({super.key});

  @override
  State<TogglesPage> createState() => _TogglesPageState();
}

class _TogglesPageState extends State<TogglesPage> {
  bool _adBlockEnabled = false;
  bool _backgroundAudioEnabled = false;
  bool _showShorts = true;
  bool _showPosts = true;
  bool _fullscreenOnRotation = false;
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
    final adBlock = await SettingsRepository.getEffectiveAdBlockEnabled();
    final backgroundAudio =
        await SettingsRepository.getEffectiveBackgroundAudioEnabled();
    if (_disposed || !mounted) return;
    setState(() {
      _adBlockEnabled = adBlock;
      _backgroundAudioEnabled = backgroundAudio;
    });
  }

  Future<void> _changeAdBlock(bool enabled) async {
    final override = RemoteConfigService.instance.adBlockOverride;
    if (override != RemoteOverride.followUser) return;
    await SettingsRepository.setAdBlockEnabled(enabled);
    if (!mounted) return;
    setState(() => _adBlockEnabled = enabled);
  }

  Future<void> _changeBackgroundAudio(bool enabled) async {
    final override = RemoteConfigService.instance.backgroundAudioOverride;
    if (override != RemoteOverride.followUser) return;
    await SettingsRepository.setBackgroundAudioEnabled(enabled);
    if (!mounted) return;
    setState(() => _backgroundAudioEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Toggles'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.movie_filter_outlined),
            title: const Text('Show shorts'),
            subtitle: const Text('Display shorts content in the hub'),
            trailing: Switch(
              value: _showShorts,
              onChanged: (value) => setState(() => _showShorts = value),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Show posts'),
            subtitle: const Text('Display posts content in the hub'),
            trailing: Switch(
              value: _showPosts,
              onChanged: (value) => setState(() => _showPosts = value),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.screen_rotation_outlined),
            title: const Text('Enter fullscreen on device rotation'),
            subtitle:
                const Text('Rotate your device to watch in fullscreen'),
            trailing: Switch(
              value: _fullscreenOnRotation,
              onChanged: (value) =>
                  setState(() => _fullscreenOnRotation = value),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Block ads & trackers'),
            subtitle:
                const Text('Off by default. Removes ads when enabled.'),
            trailing: Switch(
              value: _adBlockEnabled,
              onChanged: RemoteConfigService.instance.adBlockOverride ==
                      RemoteOverride.followUser
                  ? (value) => _changeAdBlock(value)
                  : null,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.audiotrack_outlined),
            title: const Text('Background audio'),
            subtitle: const Text('Keep playing when app is in background'),
            trailing: Switch(
              value: _backgroundAudioEnabled,
              onChanged:
                  RemoteConfigService.instance.backgroundAudioOverride ==
                          RemoteOverride.followUser
                      ? (value) => _changeBackgroundAudio(value)
                      : null,
            ),
          ),
        ],
      ),
    );
  }
}
