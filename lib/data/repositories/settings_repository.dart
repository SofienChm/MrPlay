import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import '../../core/constants/app_constants.dart';

class SettingsRepository {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  ThemeMode getThemeMode() {
    final value = _prefs?.getString(AppConstants.themeModeKey) ?? 'dark';
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    String value;
    switch (mode) {
      case ThemeMode.light:
        value = 'light';
        break;
      case ThemeMode.dark:
        value = 'dark';
        break;
      default:
        value = 'system';
    }
    await _prefs?.setString(AppConstants.themeModeKey, value);
  }

  String? getDefaultPlatform() {
    return _prefs?.getString('default_platform');
  }

  Future<void> setDefaultPlatform(String platform) async {
    await _prefs?.setString('default_platform', platform);
  }

  Future<bool> clearHistory() async {
    final historyBox = await Hive.openBox(AppConstants.historyKey);
    await historyBox.clear();
    return true;
  }
}
