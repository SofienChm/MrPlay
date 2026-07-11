import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

class AdConfig {
  AdConfig._();

  static const String _testBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _prodBannerAdUnitId =
      'ca-app-pub-2351054385499645/9979835900';

  static String get bannerAdUnitId {
    return _testBannerAdUnitId;
  }
}
