import 'services/ad_config_service.dart';

class AdConfig {
  AdConfig._();

  /// The banner unit id is driven by Firebase Remote Config (`banner_ad_unit_id`
  /// key) so the developer can swap the Google test unit for the production
  /// unit from the Firebase console. Defaults to a Google test unit when
  /// Firebase isn't configured / offline / the key is blank.
  static String get bannerAdUnitId =>
      AdConfigService.instance.bannerAdUnitId.value;
}