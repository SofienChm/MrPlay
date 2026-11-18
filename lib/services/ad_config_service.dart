import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import 'firebase_apps.dart';

/// Reads the AdMob banner unit id from Firebase Remote Config so the developer
/// can switch between banner units in the Firebase console — without shipping a
/// new APK. Defaults to the production unit whenever Firebase is missing,
/// offline, or the key isn't set. Banner visibility is also remote-controlled
/// (`banner_ad_enabled` and `hub_banner_ad_enabled`): flip them to `false` in
/// the console to hide a slot everywhere.
class AdConfigService {
  AdConfigService._();

  static final AdConfigService instance = AdConfigService._();

  static const String _bannerKey = 'banner_ad_unit_id';
  static const String _hubBannerKey = 'hub_banner_ad_unit_id';
  static const String _bannerEnabledKey = 'banner_ad_enabled';
  static const String _hubBannerEnabledKey = 'hub_banner_ad_enabled';
  static const String _hubNativeKey = 'hub_native_ad_unit_id';
  static const String _hubNativeEnabledKey = 'hub_native_ad_enabled';
  /// Google's test banner unit, handy for debugging (shows a placeholder ad on
  /// any device). Kept for reference; production builds default to
  /// [defaultBannerAdUnitId].
  static const String testBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  /// Production floating (in-browser) banner unit.
  static const String defaultBannerAdUnitId =
      'ca-app-pub-2351054385499645/9979835900';
  /// Production hub page banner unit.
  static const String defaultHubBannerAdUnitId =
      'ca-app-pub-2351054385499645/3322267441';

  /// Current effective banner unit for the floating (in-browser) banner.
  /// Listeners are notified when the remote value changes so a live banner can
  /// be reloaded with the new unit.
  final ValueNotifier<String> bannerAdUnitId =
      ValueNotifier<String>(defaultBannerAdUnitId);

  /// Current effective banner unit for the hub page banner. Same contract as
  /// [bannerAdUnitId], driven by its own console key so the two slots can go
  /// live independently.
  final ValueNotifier<String> hubBannerAdUnitId =
      ValueNotifier<String>(defaultHubBannerAdUnitId);

  /// Whether the floating banner is enabled. Remote-driven. Defaults to `true`
  /// (banners shown) so installing the flag keys in the console is optional;
  /// setting `banner_ad_enabled` to `false` hides the slot on every device.
  final ValueNotifier<bool> bannerEnabled = ValueNotifier<bool>(true);

  /// Whether the hub page banner is enabled. Remote-driven by
  /// `hub_banner_ad_enabled`, same contract as [bannerEnabled].
  final ValueNotifier<bool> hubBannerEnabled = ValueNotifier<bool>(true);

  /// Native Advanced ad unit for the hub page (Remote Config
  /// `hub_native_ad_unit_id`). Empty = no native ad until the developer sets a
  /// unit created under the Android app in AdMob.
  final ValueNotifier<String> hubNativeAdUnitId = ValueNotifier<String>('');

  /// Master switch for the hub native ad (`hub_native_ad_enabled`).
  final ValueNotifier<bool> hubNativeEnabled = ValueNotifier<bool>(true);

  StreamSubscription<RemoteConfigUpdate>? _updatesSub;

  /// Fetches remote config and keeps the notifiers in sync with the console.
  /// Fire-and-forget friendly: it never throws, and early banner loads simply
  /// get swapped to the remote key when the fetch lands.
  Future<void> init() async {
    try {
      final rc = FirebaseApps.remoteConfig;
      _updatesSub ??= rc.onConfigUpdated.listen((_) {
        _applyCurrent();
      });
      // The visibility keys only exist in the console once the developer adds
      // them. Default them to "enabled" so current installs keep showing ads
      // until the console explicitly flips a slot off.
      await rc.setDefaults(const <String, dynamic>{
        _bannerEnabledKey: true,
        _hubBannerEnabledKey: true,
        _hubNativeEnabledKey: true,
      });
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          // Don't fetch on every launch: the real-time onConfigUpdated listener
          // still pushes changes, so a 30 min floor on fetchAndActivate avoids
          // burning Firebase's fetch quota without losing console updates.
          minimumFetchInterval: const Duration(minutes: 30),
        ),
      );
      await rc.fetchAndActivate();
      _applyCurrent();
    } catch (_) {}
  }

  void _applyCurrent() {
    try {
      final rc = FirebaseApps.remoteConfig;
      final floating = _effectiveUnitOf(
        rc.getString(_bannerKey),
        fallback: defaultBannerAdUnitId,
      );
      if (bannerAdUnitId.value != floating) {
        bannerAdUnitId.value = floating;
      }
      final hub = _effectiveUnitOf(
        rc.getString(_hubBannerKey),
        fallback: defaultHubBannerAdUnitId,
      );
      if (hubBannerAdUnitId.value != hub) {
        hubBannerAdUnitId.value = hub;
      }
      final floatingEnabled = rc.getBool(_bannerEnabledKey);
      if (bannerEnabled.value != floatingEnabled) {
        bannerEnabled.value = floatingEnabled;
      }
      final native = rc.getString(_hubNativeKey).trim();
      final nativeUnit = native.startsWith('ca-app-pub-') ? native : '';
      if (hubNativeAdUnitId.value != nativeUnit) {
        hubNativeAdUnitId.value = nativeUnit;
      }
      final nativeEnabled = rc.getBool(_hubNativeEnabledKey);
      if (hubNativeEnabled.value != nativeEnabled) {
        hubNativeEnabled.value = nativeEnabled;
      }
      final hubEnabled = rc.getBool(_hubBannerEnabledKey);
      if (hubBannerEnabled.value != hubEnabled) {
        hubBannerEnabled.value = hubEnabled;
      }
    } catch (_) {}
  }

  String _effectiveUnitOf(String raw, {required String fallback}) {
    final value = raw.trim();
    return value.isNotEmpty && value.startsWith('ca-app-pub-')
        ? value
        : fallback;
  }
}
