import 'package:flutter/material.dart';

import '../../data/repositories/settings_repository.dart';

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
    final adBlock = await SettingsRepository.getAdBlockEnabled();
    final backgroundAudio =
        await SettingsRepository.getBackgroundAudioEnabled();
    final history = await SettingsRepository.getHistoryEnabled();
    if (_disposed || !mounted) return;
    setState(() {
      _adBlockEnabled = adBlock;
      _backgroundAudioEnabled = backgroundAudio;
      _historyEnabled = history;
    });
  }

  Future<void> _changeHistory(bool enabled) async {
    await SettingsRepository.setHistoryEnabled(enabled);
    if (!mounted) return;
    setState(() => _historyEnabled = enabled);
  }

  Future<void> _changeAdBlock(bool enabled) async {
    await SettingsRepository.setAdBlockEnabled(enabled);
    if (!mounted) return;
    setState(() => _adBlockEnabled = enabled);
  }

  Future<void> _changeBackgroundAudio(bool enabled) async {
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
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Watch history'),
            subtitle: const Text('Record watched videos'),
            trailing: Switch(
              value: _historyEnabled,
              onChanged: (value) => _changeHistory(value),
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
              onChanged: (value) => _changeAdBlock(value),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.audiotrack_outlined),
            title: const Text('Background audio'),
            subtitle: const Text('Keep playing when app is in background'),
            trailing: Switch(
              value: _backgroundAudioEnabled,
              onChanged: (value) => _changeBackgroundAudio(value),
            ),
          ),
        ],
      ),
    );
  }
}
