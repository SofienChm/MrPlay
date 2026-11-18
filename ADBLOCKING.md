# YouTube Ad Blocking in MrPlay

This document explains how MrPlay eliminates YouTube ads inside its embedded
WebView while **never skipping or jumping the real video**. All ad-blocking
logic lives in two files, which are the only files that need editing to change
ad-blocking behavior:

- `lib/core/constants/content_blocker_js.dart` — all the in-page JavaScript
- `lib/core/constants/webview_ad_blocker.dart` — the native network-layer blocklist
- `lib/presentation/widgets/persistent_webview.dart` — injects the JS into both
  WebView instances (browse tab + video tab)

---

## The three layers

Ad blocking is intentionally defense-in-depth. Each layer is independent and
fail-safe: if any layer errors, it must do nothing rather than guess, so the
real video is never cut short or skipped.

| Layer | What it does | Where it runs | Failure mode |
|-------|--------------|---------------|--------------|
| **1. Strip ad data** | Removes ad slots from the player response before the player reads it | In-page JS (`playerAdsStripperScript`) | Does nothing, passes response through untouched |
| **2. Block ad domains** | Drops requests to ad-server domains at the network layer | Native `WebViewAdBlocker` + JS host blocklist | Returns 204 empty response / rejects the request |
| **3. DOM hiding & auto-skip fallback** | Hides ad UI, auto-clicks skip buttons, masks unskippable ads | In-page JS (`genericAdBlockerScript`) | No-op — never freezes or skips real content |

---

## Layer 1 — Strip ad data from the player response

The most important layer. YouTube's player receives a JSON "player response"
from `/youtubei/v1/player` (and `/youtubei/v1/next`, `/youtubei/v1/get_ad_break`)
that carries the ad slots. If those ad slots are deleted before the player reads
them, the player simply never shows an ad.

This script:

- **Patches `window.ytInitialPlayerResponse`** with a getter/setter that deletes
  ad keys from whatever is assigned.
- **Overrides `window.fetch`** so any response from a `/youtubei/v1/player`,
  `/youtubei/v1/next`, or `/youtubei/v1/get_ad_break` URL is cloned, parsed, and
  the ad keys are deleted before a clean `Response` is returned.
- **Overrides `XMLHttpRequest.open` / `responseText` / `response`** so XHR-based
  API clients also get cleaned payloads (YouTube reads `.response` when
  `responseType === 'json'`, which would otherwise leak the ads through).

The whole block is wrapped in `try/catch`; on any exception it falls through to
the original behavior. On a fetch parse failure it always returns the original
untouched response — never `undefined` and never a broken response.

```dart
static const String playerAdsStripperScript = '''
  (function() {
    if (location.hostname.indexOf('youtube.com') === -1 &&
        location.hostname.indexOf('youtu.be') === -1) return;

    // player / next deliver the initial ad slots; get_ad_break delivers
    // mid-roll breaks. Stripping all three keeps the player from ever
    // receiving an ad slot, so no pre-roll / mid-roll ever plays.
    var PLAYER_RE = /\\/youtubei\\/v1\\/(player|next|get_ad_break)/;

    var AD_KEYS = [
      'adPlacements', 'playerAds', 'adSlots', 'adBreakParams',
      'adBreakHeartbeatParams', 'adParams', 'adLoggingDomain',
      'adModule', 'adJoiningInfo', 'adPlayheadUpdateParams',
      'adCuePoints', 'adBreakHeartbeat', 'adSuspendTrigger',
      'adSkippable', 'adImportantSkip', 'adOverlay', 'adVideoId',
      'adBudgetState', 'adReactiveSlots', 'adInlineContinuation',
      'adMessages', 'adExpiryTimeout', 'adBreakInfo', 'adBreakRenderer',
      'adIntroRenderer', 'adNotice', 'adSkipDenied', 'adPlayerLogging',
      'adDescriptor', 'adDurationSec', 'adId', 'adFlags', 'adType',
      'adUnit', 'adStreamUrl', 'adRenderer', 'adOptions', 'adTags',
      'adTrackingParams', 'adReasons'
    ];

    function stripAds(node) {
      if (!node) return false;
      var changed = false;
      if (Array.isArray(node)) {
        for (var i = 0; i < node.length; i++) {
          if (stripAds(node[i])) changed = true;
        }
        return changed;
      }
      if (typeof node === 'object') {
        for (var k in node) {
          if (!Object.prototype.hasOwnProperty.call(node, k)) continue;
          if (AD_KEYS.indexOf(k) !== -1) {
            delete node[k];
            changed = true;
            continue;
          }
          if (stripAds(node[k])) changed = true;
        }
      }
      return changed;
    }

    function cleanText(raw, xhr) {
      if (raw && xhr && PLAYER_RE.test(xhr.__mrpUrl)) {
        try {
          var json = JSON.parse(raw);
          if (stripAds(json)) return JSON.stringify(json);
        } catch (e) {}
      }
      return raw;
    }

    if (window.fetch) {
      var origFetch = window.fetch;
      window.fetch = function(input, init) {
        var url = (typeof input === 'string')
            ? input
            : (input && (input.url || input.href) || '');
        var result = origFetch.apply(this, arguments);
        if (!PLAYER_RE.test(url)) return result;
        return result.then(function(res) {
          if (!res || !res.ok) return res;
          return res.clone().text().then(function(text) {
            try {
              var json = JSON.parse(text);
              if (stripAds(json)) {
                var headers = new Headers(res.headers);
                headers.delete('content-encoding');
                headers.delete('content-length');
                return new Response(JSON.stringify(json), {
                  status: res.status,
                  statusText: res.statusText,
                  headers: headers
                });
              }
            } catch (e) {}
            return res;
          });
        });
      };
    }

    if (XMLHttpRequest && XMLHttpRequest.prototype) {
      var proto = XMLHttpRequest.prototype;
      var origOpen = proto.open;
      proto.open = function(method, url, async, user, pass) {
        this.__mrpUrl = (url != null) ? String(url) : '';
        return origOpen.apply(this, arguments);
      };

      var origTextDesc = Object.getOwnPropertyDescriptor(proto, 'responseText');
      if (origTextDesc && origTextDesc.get) {
        Object.defineProperty(proto, 'responseText', {
          configurable: true,
          get: function() {
            var raw;
            try { raw = origTextDesc.get.call(this); } catch (e) { return null; }
            return cleanText(raw, this);
          }
        });
      }

      var origRespDesc = Object.getOwnPropertyDescriptor(proto, 'response');
      if (origRespDesc && origRespDesc.get) {
        Object.defineProperty(proto, 'response', {
          configurable: true,
          get: function() {
            var raw;
            try { raw = origRespDesc.get.call(this); } catch (e) { return null; }
            if (raw && this.__mrpUrl && PLAYER_RE.test(this.__mrpUrl)) {
              if (typeof raw === 'string') {
                return cleanText(raw, this);
              }
              if (this.responseType === 'json' && typeof raw === 'object') {
                stripAds(raw);
              }
            }
            return raw;
          }
        });
      }
    }
  })();
''';
```

---

## Layer 2 — Block known ad domains at the network level (native)

In addition to the JS stripping, MrPlay blocks ad-server domains at the WebView
network layer via Android's `shouldInterceptRequest` callback. Requests whose
host matches the blocklist get a **204 No Content** response before their bytes
are downloaded, so ad media never reaches the page. Anything served from the
real video CDN (`googlevideo.com`) is **never** blocked, because that also
carries the actual video and blocking it would break playback.

```dart
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
```

Both WebViews (browse tab + video tab) wire this in via their
`shouldInterceptRequest` callback:

```dart
shouldInterceptRequest: (controller, request) async {
  return WebViewAdBlocker.intercept(request);
},
```

---

## Layer 3 — Hide ad UI, auto-skip skippable ads, and mask the fallback

The second in-page script handles the DOM side of ad blocking:

1. **Hides ad DOM elements** (banners, containers, skip-button slots, iframes
   from blocked hosts) and re-scans on a debounced `MutationObserver`.
2. **Auto-clicks skippable ads** (`.ytp-ad-skip-button` variants).
3. **Fast-forwards unskippable ads** — as a *fallback only*, when an ad slips
   through every other layer. This is the riskiest path (a bug here could skip
   real content), so it is heavily guarded:

   - Only applies a `16x` `playbackRate` hack while a real video ad is active
     (detected via the `ad-showing` / `ad-interrupting` classes).
   - Mutes the video while the ad plays (so the 16x chipmunk audio isn't
     blasted at the user) and restores the previous mute state when the ad ends.
   - Is skipped entirely on YouTube Music (which uses an `<audio>` element and
     shares `.ytp-*` classes, so it would falsely speed up music).

> **Important:** The current codebase implements the safe auto-skip / masked
> fallback using **media-state detection** (`ad-showing` / `ad-interrupting`
> classes) rather than a blind currentTime jump. The duration-sanity guard
> (only skip if `video.duration` is finite, `> 0`, and `<= 121s`) is the
> recommended hardening — a placeholder for teams extending this script — to
> guarantee that a short/real video is never mistaken for an ad and skipped.

```dart
static const String genericAdBlockerScript = '''
  (function() {
    var BLOCKED_HOSTS = /(doubleclick\\.net|googlesyndication\\.com|googleadservices\\.com|adservice\\.google|amazon-adsystem\\.com|adnxs\\.com|adform\\.net|taboola\\.com|outbrain\\.com|pubmatic\\.com|criteo\\.com|rubiconproject\\.com|adsrvr\\.org|tremorhub\\.com|springserve\\.com)/i;

    var SELECTORS = [
      '[data-ad-slot]',
      '[data-ad-client]',
      '[data-ad-zone]',
      '[data-google-query-id]',
      '[data-ad-unit]',
      '.adsbygoogle',
      '[class*="ad-slot"]',
      '[class*="ad-banner"]',
      '[class*="ad-container"]',
      '[class*="advert"]',
      '[class*="sponsored"]',
      '[class*="sponsor"]',
      '[id*="google_ads"]',
      '[id*="google_ads_iframe"]',
      '[id*="advert"]',
      'iframe[src*="doubleclick.net"]',
      'iframe[src*="googlesyndication.com"]',
      'iframe[src*="googleadservices.com"]',
      'iframe[src*="adservice.google"]',
      'iframe[src*="amazon-adsystem"]',
      'iframe[src*="taboola"]',
      'iframe[src*="outbrain"]',
      'iframe[src*="adnxs"]',
      'ytd-display-ad-renderer',
      'ytd-promoted-sparkles-web-renderer',
      'ytd-video-masthead-ad-renderer',
      'ytd-banner-promo-renderer',
      'ytd-ad-slot-renderer',
      'ytd-in-feed-ad-layout-renderer',
      'ytm-promoted-video-renderer',
      'ytm-display-ad-renderer',
      'ytm-companion-ad-renderer',
      'ytm-ad-overlay',
      '.video-ads',
      '.ytp-ad-module',
      '.ytp-ad-overlay-container',
      '.ytp-ad-text-overlay',
      '.ytp-ad-skip-button-slot',
      '#player-ads',
      '.ytp-ad-progress-list',
      '.ytp-ad-duration-remaining',
      '.ytp-ad-simple-ad-badge',
      '.ytp-ad-player-overlay'
    ];

    function hide(el) {
      try {
        el.style.display = 'none';
        el.style.visibility = 'hidden';
        el.style.opacity = '0';
        el.setAttribute('aria-hidden', 'true');
      } catch (e) {}
    }

    function hideAdIframes() {
      try {
        document.querySelectorAll('iframe').forEach(function(f) {
          if (BLOCKED_HOSTS.test(f.src || '')) hide(f);
        });
      } catch (e) {}
    }

    function blockAds() {
      try {
        SELECTORS.forEach(function(sel) {
          document.querySelectorAll(sel).forEach(hide);
        });
        hideAdIframes();
      } catch (e) {}
    }

    blockAds();

    // Debounced re-scan: YouTube Music (and other heavy SPAs) mutate the DOM
    // constantly, and running the full selector sweep on every mutation
    // requestAnimationFrame would otherwise choke the main thread. At most one
    // blockAds() pass runs per animation frame, throttled to every 250ms.
    var blockScheduled = false;
    var lastBlockAt = 0;
    function requestBlock() {
      if (blockScheduled) return;
      blockScheduled = true;
      requestAnimationFrame(function() {
        blockScheduled = false;
        var now = Date.now();
        if (now - lastBlockAt < 250) return;
        lastBlockAt = now;
        blockAds();
      });
    }

    new MutationObserver(requestBlock)
      .observe(document.documentElement, { childList: true, subtree: true });

    // Auto-skip skippable ads and fast-forward unskippable ones (16x playback
    // finishes a 30s ad in ~2s). While an ad slips through, mute it so the
    // 16x chipmunk audio isn't blasted at the user, then restore the previous
    // (un)muted state once the ad ends.
    var mutedForAd = false;
    setInterval(function() {
      var btn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-container button, .ytm-skip-ad-button');
      if (btn) { try { btn.click(); } catch (e) {} }

      // YouTube Music uses an <audio> element and its player shares .ytp-*
      // classes with the video player, so the fast-forward hack would falsely
      // speed up music. Skip it there entirely.
      if (location.hostname.indexOf('music.youtube') === 0) return;

      var video = document.querySelector('video');
      if (!video) return;
      // Only speed up when a real video ad is active (YouTube adds the
      // ad-showing / ad-interrupting class to the <video> element).
      var adShowing = video.classList.contains('ad-showing') ||
                      video.classList.contains('ad-interrupting') ||
                      !!document.querySelector('.ytp-ad-player-overlay-layout');
      if (adShowing) {
        if (video.playbackRate !== 16) video.playbackRate = 16;
        if (!video.muted) { video.muted = true; mutedForAd = true; }
      } else {
        if (video.playbackRate === 16) video.playbackRate = 1;
        if (mutedForAd && video.muted) { video.muted = false; mutedForAd = false; }
      }
    }, 300);
  })();
''';
```

---

## Injection into the WebViews

All ad scripts are injected at `AT_DOCUMENT_START` (before the page runs) so they
are in place before YouTube loads its player. They are registered in **both**
WebView instances — the browse tab and the video tab — because the video can be
routed into either depending on how it was opened.

Browse tab (`persistent_webview.dart`, browse `InAppWebView`):

```dart
initialUserScripts: UnmodifiableListView([
  UserScript(
    source: ContentBlockerJS.playerAdsStripperScript,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  ),
  UserScript(
    source: ContentBlockerJS.genericAdBlockerScript,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  ),
  // ... unrelated watch-page scripts (visibility keep-alive, banner remover,
  //     player controls, media observer) ...
]),
```

Video tab (`persistent_webview.dart`, video-tab `InAppWebView`):

```dart
initialUserScripts: UnmodifiableListView([
  UserScript(
    source: VideoTabJS.headerRemoverScript,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  ),
  UserScript(
    source: VideoTabJS.swipeCollapseScript,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  ),
  UserScript(
    source: ContentBlockerJS.playerAdsStripperScript,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  ),
  UserScript(
    source: ContentBlockerJS.genericAdBlockerScript,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  ),
  // ... unrelated watch-page scripts ...
]),
```

---

## Ordering & why it matters

The scripts are ordered so each layer runs before, and is complemented by, the
next:

1. **`playerAdsStripperScript`** (Layer 1) runs first so the player response is
   clean before it is read.
2. **`genericAdBlockerScript`** (Layer 3) hides / skips anything that still
   appears in the DOM.
3. The **native `WebViewAdBlocker`** (Layer 2) drops ad-network requests
   underneath both, at the transport layer.

Because Layer 1 strips the ad slots from the response, Layer 3 rarely has to do
anything more than hide a stray banner — but it is there as a safety net, so an
ad that slips past one layer still gets caught by the next. No layer relies on
another being perfect.

---

## FAQ

**Does this ever skip my real video?**
No. Layer 1 removes ads *before* playback starts (no skip needed). Layer 3's
auto-skip only clicks YouTube's native skip button, and its fast-forward hack is
guarded to only act while an ad is genuinely active and to never touch the real
video. There is no blind `currentTime` jump onto real content.

**Does this break the video CDN?**
No. `googlevideo.com` (the real video CDN) is deliberately **not** in the
blocklist — it also serves the actual video, so blocking it would break
playback.

**Why both native blocking and JS blocking?**
The native `WebViewAdBlocker` drops ad requests at the network layer; the JS
stripper/hider handles ad content that is already embedded in YouTube's own
responses/HTML. Together they cover both routes ads can arrive.
```
