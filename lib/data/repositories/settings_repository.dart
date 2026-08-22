import 'package:shared_preferences/shared_preferences.dart';
import '../../services/remote_config_service.dart';

class SettingsRepository {
  static const String _themeKey = 'theme_mode';
  static const String _defaultPlatformKey = 'default_platform';
  static const String _lastPlatformUrlKey = 'last_platform_url';
  static const String _adBlockKey = 'ad_block_enabled';
  static const String _backgroundAudioKey = 'background_audio_enabled';
  static const String _historyKey = 'history_enabled';
  static const String _accentColorKey = 'accent_color';
  static const String _hubBackgroundKey = 'hub_background';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<String> getThemeMode() async {
    final prefs = await _prefs;
    return prefs.getString(_themeKey) ?? 'system';
  }

  static Future<void> setThemeMode(String mode) async {
    final prefs = await _prefs;
    await prefs.setString(_themeKey, mode);
  }

  static Future<String> getDefaultPlatform() async {
    final prefs = await _prefs;
    return prefs.getString(_defaultPlatformKey) ?? 'YouTube';
  }

  static Future<void> setDefaultPlatform(String name) async {
    final prefs = await _prefs;
    await prefs.setString(_defaultPlatformKey, name);
  }

  static Future<String?> getLastPlatformUrl() async {
    final prefs = await _prefs;
    return prefs.getString(_lastPlatformUrlKey);
  }

  static Future<void> setLastPlatformUrl(String url) async {
    final prefs = await _prefs;
    await prefs.setString(_lastPlatformUrlKey, url);
  }

  static Future<bool> getAdBlockEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_adBlockKey) ?? false;
  }

  /// Effective "Block ads & trackers" state.
  ///
  /// A Remote Config override set to "true"/"false" always wins; only when the
  /// param is "default" does the user's local toggle apply.
  static Future<bool> getEffectiveAdBlockEnabled() async {
    final override = RemoteConfigService.instance.adBlockOverride;
    if (override == RemoteOverride.forceTrue) return true;
    if (override == RemoteOverride.forceFalse) return false;
    return getAdBlockEnabled();
  }

  static Future<void> setAdBlockEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_adBlockKey, enabled);
  }

  static Future<bool> getBackgroundAudioEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_backgroundAudioKey) ?? false;
  }

  /// Effective "Background audio" state.
  ///
  /// A Remote Config override set to "true"/"false" always wins; only when the
  /// param is "default" does the user's local toggle apply.
  static Future<bool> getEffectiveBackgroundAudioEnabled() async {
    final override = RemoteConfigService.instance.backgroundAudioOverride;
    if (override == RemoteOverride.forceTrue) return true;
    if (override == RemoteOverride.forceFalse) return false;
    return getBackgroundAudioEnabled();
  }

  static Future<void> setBackgroundAudioEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_backgroundAudioKey, enabled);
  }

  static Future<void> clearCache() async {
    final prefs = await _prefs;
    await prefs.remove(_themeKey);
    await prefs.remove(_defaultPlatformKey);
    await prefs.remove(_lastPlatformUrlKey);
    await prefs.remove(_adBlockKey);
    await prefs.remove(_backgroundAudioKey);
    await prefs.remove(_accentColorKey);
    await prefs.remove(_hubBackgroundKey);
  }

  static Future<bool> getHistoryEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_historyKey) ?? true;
  }

  static Future<void> setHistoryEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_historyKey, enabled);
  }

  static const int defaultAccentColor = 0xFF2196F3;

  static Future<int> getAccentColor() async {
    final prefs = await _prefs;
    return prefs.getInt(_accentColorKey) ?? defaultAccentColor;
  }

  static Future<void> setAccentColor(int value) async {
    final prefs = await _prefs;
    await prefs.setInt(_accentColorKey, value);
  }

  static Future<int> getHubBackground() async {
    final prefs = await _prefs;
    return prefs.getInt(_hubBackgroundKey) ?? 0;
  }

  static Future<void> setHubBackground(int index) async {
    final prefs = await _prefs;
    await prefs.setInt(_hubBackgroundKey, index);
  }
}
