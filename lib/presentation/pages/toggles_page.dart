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
