import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Network-level ad blocking for the two WebViews.
///
/// This runs through Android's `shouldInterceptRequest`, i.e. the same layer
/// Brave's Shields operates at: the request is dropped before its bytes are
/// downloaded. Anything in [_blockedHosts] gets a 204 No Content response, so
/// ad media (video/audio/scripts/iframes) never reaches the page.
class WebViewAdBlocker {
  static final RegExp _blockedHosts = RegExp(
    r'(doubleclick\.net|'
    r'googlesyndication\.com|'
    r'googleadservices\.com|'
    r'adservice\.google|'
    r'amazon-adsystem\.com|'
    r'adnxs\.com|'
    r'adform\.net|'
    r'taboola\.com|'
    r'outbrain\.com|'
    r'pubmatic\.com|'
    r'criteo\.com|'
    r'rubiconproject\.com|'
    r'adsrvr\.org|'
    r'tremorhub\.com|'
    r'springserve\.com)',
    caseSensitive: false,
  );

  /// Returns a blank 204 response for ad-server requests, otherwise null
  /// (meaning: let the request through untouched).
  static WebResourceResponse? intercept(WebResourceRequest? request) {
    final req = request;
    if (req == null || req.isForMainFrame == true) return null;
    final url = req.url;
    final scheme = url.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final host = url.host;
    if (host.isEmpty || !_blockedHosts.hasMatch(host)) return null;
    return WebResourceResponse(
      contentType: 'text/plain',
      contentEncoding: 'utf-8',
      statusCode: 204,
      reasonPhrase: 'NO CONTENT',
      data: Uint8List(0),
    );
  }
}