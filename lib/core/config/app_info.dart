/// Static app identity and external links.
abstract final class AppInfo {
  static const String name = 'MrPlay';
  static const String version = '2.0.0';
  static const String tagline = 'Your all-in-one video hub';

  static const String appStoreId = '6787549496';
  static const String appStoreUrl = 'https://apps.apple.com/it/app/mrplay/id$appStoreId';
  static const String privacyPolicyUrl = 'https://mrplay.app-miniminds.com/';
  static const String supportEmail = 'mrplayapp@gmail.com';

  /// Shared App Group used by the home-screen widget extension.
  static const String appGroupId = 'group.com.mrplay.shared';
  static const String homeWidgetKind = 'MrPlayRecentWidget';

  /// Safari user agent so sites serve their full mobile web experience.
  static const String webUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
}
