/// Pure navigation / popup rules for the in-app browser.
abstract final class WebPolicy {
  /// Ad, tracker and popup-flood networks. Clearly ad-serving only, so real
  /// content platforms and googlevideo.com (the video CDN) never match.
  static const Set<String> adDomains = {
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'google-analytics.com', 'adservice.google.com', 'amazon-adsystem.com',
    'adnxs.com', 'adform.net', 'taboola.com', 'outbrain.com', 'pubmatic.com',
    'criteo.com', 'rubiconproject.com', 'adsrvr.org', 'tremorhub.com',
    'springserve.com', 'popads.net', 'popcash.net', 'popunder.net',
    'propellerads.com', 'adsterra.com', 'exoclick.com', 'exosrv.com',
    'juicyads.com', 'admaven.com', 'ad-maven.com', 'mgid.com', 'revcontent.com',
    'popmyads.com', 'adscendmedia.com', 'contextweb.com', 'openx.net',
    'smartadserver.com', 'zedo.com', 'quantserve.com', 'scorecardresearch.com',
    'casalemedia.com', 'serving-sys.com',
  };

  static const Duration popupFloodGap = Duration(milliseconds: 1200);

  static bool isAdDomain(String host) {
    final h = host.toLowerCase();
    for (final d in adDomains) {
      if (h == d || h.endsWith('.$d')) return true;
    }
    return false;
  }

  /// Whether a page-initiated navigation may proceed. Dangerous schemes are
  /// always cancelled; ad domains only while popup blocking is on.
  static bool allowNavigation({
    required String? scheme,
    required String? host,
    required bool blockAdDomains,
  }) {
    switch (scheme) {
      case 'javascript':
      case 'data':
      case 'blob':
        return false;
      case 'http':
      case 'https':
        return !(blockAdDomains && host != null && host.isNotEmpty && isAdDomain(host));
      default:
        return true;
    }
  }

  /// Whether a new-window request may load. Blank popups are refused too:
  /// flood sites open about:blank and redirect it to an ad afterwards.
  static bool allowPopup({
    required String? host,
    required Duration sinceLastAllowed,
  }) {
    if (host == null || host.isEmpty || isAdDomain(host)) return false;
    return sinceLastAllowed >= popupFloodGap;
  }
}
