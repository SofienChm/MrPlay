class AdConfig {
  AdConfig._();

  /// The banner slot is intentionally a Google test unit (same as the original
  /// app). The release build previously fell back to the prod unit
  /// `ca-app-pub-2351054385499645/9979835900` while Info.plist still declared
  /// a test GADApplicationIdentifier, which made AdMob fail every load with
  /// "app ID mismatch" -> the banner silently disappeared in release builds.
  static const String bannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
}