import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/platforms.dart';
import '../../core/theme/palettes.dart';

/// Immutable snapshot of every user preference.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.accentColor = AccentColors.fallback,
    this.hubBackground = 0,
    this.defaultPlatform = Platforms.defaultName,
    this.adBlock = true,
    this.blockPopups = true,
    this.backgroundAudio = true,
    this.historyEnabled = true,
    this.fullscreenOnRotation = true,
  });

  final ThemeMode themeMode;
  final Color accentColor;
  final int hubBackground;
  final String defaultPlatform;
  final bool adBlock;
  final bool blockPopups;
  final bool backgroundAudio;
  final bool historyEnabled;
  final bool fullscreenOnRotation;

  AppSettings copyWith({
    ThemeMode? themeMode,
    Color? accentColor,
    int? hubBackground,
    String? defaultPlatform,
    bool? adBlock,
    bool? blockPopups,
    bool? backgroundAudio,
    bool? historyEnabled,
    bool? fullscreenOnRotation,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        accentColor: accentColor ?? this.accentColor,
        hubBackground: hubBackground ?? this.hubBackground,
        defaultPlatform: defaultPlatform ?? this.defaultPlatform,
        adBlock: adBlock ?? this.adBlock,
        blockPopups: blockPopups ?? this.blockPopups,
        backgroundAudio: backgroundAudio ?? this.backgroundAudio,
        historyEnabled: historyEnabled ?? this.historyEnabled,
        fullscreenOnRotation: fullscreenOnRotation ?? this.fullscreenOnRotation,
      );
}

/// Persists [AppSettings] in SharedPreferences (same keys as v1).
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _theme = 'theme_mode';
  static const _defaultPlatform = 'default_platform';
  static const _adBlock = 'ad_block_enabled';
  static const _blockPopups = 'block_popups_enabled';
  static const _backgroundAudio = 'background_audio_enabled';
  static const _history = 'history_enabled';
  static const _fullscreenOnRotation = 'fullscreen_on_rotation';
  static const _accent = 'accent_color';
  static const _hubBackground = 'hub_background';

  /// Keys reset by "Clear cache" (toggles are kept).
  static const _appearanceKeys = [_theme, _defaultPlatform, _accent, _hubBackground];

  AppSettings load() {
    const d = AppSettings();
    return AppSettings(
      themeMode: switch (_prefs.getString(_theme)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      accentColor: Color(_prefs.getInt(_accent) ?? d.accentColor.toARGB32()),
      hubBackground: _prefs.getInt(_hubBackground) ?? d.hubBackground,
      defaultPlatform: _prefs.getString(_defaultPlatform) ?? d.defaultPlatform,
      adBlock: _prefs.getBool(_adBlock) ?? d.adBlock,
      blockPopups: _prefs.getBool(_blockPopups) ?? d.blockPopups,
      backgroundAudio: _prefs.getBool(_backgroundAudio) ?? d.backgroundAudio,
      historyEnabled: _prefs.getBool(_history) ?? d.historyEnabled,
      fullscreenOnRotation: _prefs.getBool(_fullscreenOnRotation) ?? d.fullscreenOnRotation,
    );
  }

  Future<void> save(AppSettings s) async {
    await Future.wait([
      _prefs.setString(_theme, s.themeMode.name),
      _prefs.setInt(_accent, s.accentColor.toARGB32()),
      _prefs.setInt(_hubBackground, s.hubBackground),
      _prefs.setString(_defaultPlatform, s.defaultPlatform),
      _prefs.setBool(_adBlock, s.adBlock),
      _prefs.setBool(_blockPopups, s.blockPopups),
      _prefs.setBool(_backgroundAudio, s.backgroundAudio),
      _prefs.setBool(_history, s.historyEnabled),
      _prefs.setBool(_fullscreenOnRotation, s.fullscreenOnRotation),
    ]);
  }

  Future<void> resetAppearance() async {
    for (final key in _appearanceKeys) {
      await _prefs.remove(key);
    }
  }
}
