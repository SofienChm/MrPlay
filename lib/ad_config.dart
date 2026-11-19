class AdConfig {
  AdConfig._();

  /// Floating bottom banner overlay shown over the webview when the hub is not
  /// visible. Served with `AdSize.largeBanner`.
  static const String bannerAdUnitId =
      'ca-app-pub-2351054385499645/8756107312';

  /// Banner slot on the hub page, under the search bar. Served with
  /// `AdSize.banner`.
  static const String hubBannerAdUnitId =
      'ca-app-pub-2351054385499645/4819742051';

  /// Native Advanced slot on the hub page (small template).
  static const String hubNativeAdUnitId =
      'ca-app-pub-2351054385499645/6399771207';

  /// Floating Native Advanced ad over the webview / video tab. Shares the hub
  /// unit until its own "floating native" unit is created in AdMob.
  static const String floatingNativeAdUnitId = hubNativeAdUnitId;
}