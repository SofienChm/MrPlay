/// AdMob ad unit IDs. Only non-intrusive formats (banner / native).
abstract final class AdUnits {
  /// Floating banner shown over the browser (AdSize.largeBanner).
  static const String floatingBanner = 'ca-app-pub-2351054385499645/8756107312';

  /// Banner slot on the hub page (AdSize.banner).
  static const String hubBanner = 'ca-app-pub-2351054385499645/4819742051';

  /// Native Advanced slot on the hub page, rendered by the native factory below.
  static const String hubNative = 'ca-app-pub-2351054385499645/6399771207';

  /// Must match the factory registered in AppDelegate.swift.
  static const String nativeFactoryId = 'mrplayNative';
}
