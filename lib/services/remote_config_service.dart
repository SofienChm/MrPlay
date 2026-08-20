import 'package:flutter/foundation.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

/// How a remote config parameter should treat the user's local preference.
enum RemoteOverride {
  /// Parameter is set to "default" in the console: use the user's in-app
  /// toggle (which itself defaults to off).
  followUser,

  /// Parameter forces the feature ON regardless of the local toggle.
  forceTrue,

  /// Parameter forces the feature OFF regardless of the local toggle.
  forceFalse,
}

/// Central gateway for Firebase Remote Config.
///
/// Every parameter fetched from the console must be declared here with a safe
/// local default so the app keeps working fully offline or before the first
/// successful fetch.
class RemoteConfigService {
  RemoteConfigService._();

  static final RemoteConfigService instance = RemoteConfigService._();

  static const String _adBlockKey = 'ad_block';
  static const String _backgroundAudioKey = 'background_audio';
  static const String _localDefault = 'default';

  bool _fetched = false;

  bool get hasFetched => _fetched;

  /// "Block ads & trackers" override set in the Remote Config console.
  RemoteOverride get adBlockOverride => _overrideOf(_adBlockKey);

  /// "Background audio" override set in the Remote Config console.
  RemoteOverride get backgroundAudioOverride => _overrideOf(_backgroundAudioKey);

  RemoteOverride _overrideOf(String key) {
    if (!hasFetched) return RemoteOverride.followUser;
    final value = FirebaseRemoteConfig.instance.getString(key);
    switch (value) {
      case 'true':
        return RemoteOverride.forceTrue;
      case 'false':
        return RemoteOverride.forceFalse;
      default:
        return RemoteOverride.followUser;
    }
  }

  /// Fetches and activates remote values. Never throws: any error (offline,
  /// not configured) is swallowed so startup is never blocked.
  Future<void> initialize() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );

      await remoteConfig.setDefaults(const {
        _adBlockKey: _localDefault,
        _backgroundAudioKey: _localDefault,
      });

      final updated = await remoteConfig.fetchAndActivate();
      debugPrint('MrPlay remote config fetched (activated=$updated)');
      _fetched = true;
    } catch (e) {
      debugPrint('MrPlay remote config failed: $e');
    }
  }
}