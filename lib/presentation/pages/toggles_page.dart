import 'package:flutter/material.dart';

import '../../app.dart';
import '../../data/repositories/settings_repository.dart';
import '../../services/media_controls_service.dart';

/// Privacy & Security → Toggles: hosts the playback/privacy switches
/// ("Block ads & trackers", "Background audio", "Enter fullscreen on device
/// rotation" and "Watch history") on their own page. Mirrors the iOS app.
class TogglesPage extends StatefulWidget {
  const TogglesPage({super.key});

  @override
  State<TogglesPage> createState() => _TogglesPageState();
}

class _TogglesPageState extends State<TogglesPage> {
  bool _adBlockEnabled = true;
  bool _backgroundAudioEnabled = true;
  bool _fullscreenOnRotation = true;
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
    final fullscreenOnRotation =
        await SettingsRepository.getFullscreenOnRotation();
    if (_disposed || !mounted) return;
    setState(() {
      _adBlockEnabled = adBlock;
      _backgroundAudioEnabled = backgroundAudio;
      _historyEnabled = history;
      _fullscreenOnRotation = fullscreenOnRotation;
    });
  }

  Future<void> _changeHistory(bool enabled) async {
    await SettingsRepository.setHistoryEnabled(enabled);
    if (!mounted) return;
    setState(() => _historyEnabled = enabled);
  }

  Future<void> _changeFullscreenOnRotation(bool enabled) async {
    await SettingsRepository.setFullscreenOnRotation(enabled);
    MrPlayApp.fullscreenOnRotationNotifier.value = enabled;
    if (!mounted) return;
    setState(() => _fullscreenOnRotation = enabled);
  }

  Future<void> _changeAdBlock(bool enabled) async {
    await SettingsRepository.setAdBlockEnabled(enabled);
    // Apply immediately to the live webviews (no app restart needed).
    await MrPlayApp.webViewKey.currentState?.applySettingsChanges();
    if (!mounted) return;
    setState(() => _adBlockEnabled = enabled);
  }

  Future<void> _changeBackgroundAudio(bool enabled) async {
    await SettingsRepository.setBackgroundAudioEnabled(enabled);
    // Reflect immediately on the native side so the foreground service /
    // media notification start or stop right away.
    try {
      await MediaControlsService.instance.setBackgroundAudioEnabled(enabled);
    } catch (_) {}
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
            leading: const Icon(Icons.screen_rotation_outlined),
            title: const Text('Enter fullscreen on device rotation'),
            subtitle: const Text('Rotate your device to watch in fullscreen'),
            trailing: Switch(
              value: _fullscreenOnRotation,
              onChanged: (value) => _changeFullscreenOnRotation(value),
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
            subtitle: const Text(
                'On by default. Removes ads when enabled. Takes effect on the '
                'next video you play.'),
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