import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const String _themeKey = 'theme_mode';
  static const String _defaultPlatformKey = 'default_platform';
  static const String _lastPlatformUrlKey = 'last_platform_url';
  static const String _adBlockKey = 'ad_block_enabled';
  static const String _backgroundAudioKey = 'background_audio_enabled';

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

  static Future<void> setAdBlockEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_adBlockKey, enabled);
  }

  static Future<bool> getBackgroundAudioEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_backgroundAudioKey) ?? false;
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
  }
}
