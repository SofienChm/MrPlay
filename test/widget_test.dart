import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:hive/hive.dart';
import 'package:mrplay/app.dart';
import 'package:mrplay/core/constants/content_blocker_js.dart';
import 'package:mrplay/presentation/widgets/persistent_webview.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() {
    hiveDir = Directory.systemTemp.createTempSync('mrplay_hive_test');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  testWidgets('App renders hub page', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MrPlayApp()));
    expect(find.text('MrPlay'), findsOneWidget);
  });

  test('shared links only open for explicit actions', () {
    expect(shouldOpenSharedLink('play'), isTrue);
    expect(shouldOpenSharedLink('open'), isTrue);
    expect(shouldOpenSharedLink(null), isFalse);
    expect(shouldOpenSharedLink('queued'), isFalse);
  });

  test('player events only come from the active WebView surface', () {
    final browseController = Object();
    final videoController = Object();

    expect(
      PersistentWebViewState.acceptsPlayerEvents(
        source: browseController,
        browseController: browseController,
        videoController: videoController,
        videoTabActive: false,
      ),
      isTrue,
    );
    expect(
      PersistentWebViewState.acceptsPlayerEvents(
        source: videoController,
        browseController: browseController,
        videoController: videoController,
        videoTabActive: false,
      ),
      isFalse,
    );
    expect(
      PersistentWebViewState.acceptsPlayerEvents(
        source: videoController,
        browseController: browseController,
        videoController: videoController,
        videoTabActive: true,
      ),
      isTrue,
    );
    expect(
      PersistentWebViewState.acceptsPlayerEvents(
        source: browseController,
        browseController: browseController,
        videoController: videoController,
        videoTabActive: true,
      ),
      isFalse,
    );
  });

  test('popup windows block ads and missing urls but allow normal links', () {
    expect(
      PersistentWebViewState.shouldLoadPopupUrl(
        url: null,
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isFalse,
    );
    expect(
      PersistentWebViewState.shouldLoadPopupUrl(
        url: WebUri('https://ad.doubleclick.net/pixel'),
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isFalse,
    );
    expect(
      PersistentWebViewState.shouldLoadPopupUrl(
        url: WebUri('https://m.youtube.com/watch?v=abc'),
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isTrue,
    );
  });

  test('blank and ad popups are blocked, legit popups allowed', () {
    // about:blank popups (the ad-popup redirect pattern) must be blocked.
    expect(
      PersistentWebViewState.shouldLoadPopupUrl(
        url: WebUri('about:blank'),
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isFalse,
    );
    // Popup/popunder ad networks must be blocked.
    expect(
      PersistentWebViewState.shouldLoadPopupUrl(
        url: WebUri('https://ads.propellerads.com/x'),
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isFalse,
    );
    // Real content platforms must never be blocked.
    expect(
      PersistentWebViewState.shouldLoadPopupUrl(
        url: WebUri('https://www.youtube.com/'),
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isTrue,
    );
    expect(
      PersistentWebViewState.shouldLoadPopupUrl(
        url: WebUri('https://www.twitch.tv/'),
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isTrue,
    );
  });

  test('navigations to ad domains are cancelled, legit ones allowed', () {
    // Ad redirects / popup landing pages are cancelled in the webview.
    expect(
      PersistentWebViewState.shouldAllowNavigation(
        scheme: 'https',
        host: 'click.doubleclick.net',
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isFalse,
    );
    expect(
      PersistentWebViewState.shouldAllowNavigation(
        scheme: 'http',
        host: 'cdn.popads.net',
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isFalse,
    );
    // Dangerous schemes are cancelled.
    expect(
      PersistentWebViewState.shouldAllowNavigation(
        scheme: 'javascript',
        host: '',
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isFalse,
    );
    expect(
      PersistentWebViewState.shouldAllowNavigation(
        scheme: 'data',
        host: '',
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isFalse,
    );
    // Core flows: platforms, YouTube, video content CDNs all pass.
    expect(
      PersistentWebViewState.shouldAllowNavigation(
        scheme: 'https',
        host: 'www.youtube.com',
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isTrue,
    );
    expect(
      PersistentWebViewState.shouldAllowNavigation(
        scheme: 'https',
        host: 'm.youtube.com',
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isTrue,
    );
    expect(
      PersistentWebViewState.shouldAllowNavigation(
        scheme: 'https',
        host: 'rr2---sn-googlevideo.com',
        isAdDomain: PersistentWebViewState.isAdDomain,
      ),
      isTrue,
    );
  });

  test('script popup blocker only allows user-intended popups', () {
    final script = ContentBlockerJS.popupBlockerScript;
    // Arbitrary script popups (no recent real tap) are blocked.
    expect(script, contains('if (now - lastTapAt > TAP_WINDOW) return null;'));
    // A popup must match the link the user actually tapped...
    expect(
      script,
      contains('var anchorMatch = lastAnchorUrl !== \'\' && '
          'resolved.indexOf(lastAnchorUrl) === 0;'),
    );
    // ...or a trusted auth host; anything else is blocked.
    expect(
      script,
      contains('if (!anchorMatch && !TRUSTED_HOSTS.test(host)) return null;'),
    );
    // Flood guard limits one popup per short window.
    expect(script, contains('if (now - lastAllowedAt < FLOOD_GAP) return null;'));
  });

  test('popup flood guard allows one popup per window', () {
    const gap = Duration(milliseconds: 1200);
    // First popup (nothing recently): allowed.
    expect(
      PersistentWebViewState.shouldAllowPopup(
        sinceLastAllowed: gap,
        floodGap: gap,
      ),
      isTrue,
    );
    // Rapid follow-up popup (the flood): blocked.
    expect(
      PersistentWebViewState.shouldAllowPopup(
        sinceLastAllowed: Duration(milliseconds: 200),
        floodGap: gap,
      ),
      isFalse,
    );
  });

  test('remote seek targets are clamped to the video duration', () {
    const duration = Duration(minutes: 10);
    expect(
      PersistentWebViewState.clampSeekTarget(
        Duration.zero,
        duration,
      ),
      Duration.zero,
    );
    expect(
      PersistentWebViewState.clampSeekTarget(
        const Duration(seconds: -5),
        duration,
      ),
      Duration.zero,
    );
    expect(
      PersistentWebViewState.clampSeekTarget(
        const Duration(minutes: 4, seconds: 30),
        duration,
      ),
      const Duration(minutes: 4, seconds: 30),
    );
    expect(
      PersistentWebViewState.clampSeekTarget(
        const Duration(minutes: 15),
        duration,
      ),
      duration,
    );
    // Unknown (zero) duration must not clamp, so seeking before metadata
    // arrives still reaches the video element.
    expect(
      PersistentWebViewState.clampSeekTarget(
        const Duration(minutes: 15),
        Duration.zero,
      ),
      const Duration(minutes: 15),
    );
  });

  test('unmute script never fights the ad-blocker or mutes unrelated widgets',
      () {
    final script = PersistentWebViewState.unmuteVideoScript;
    // Must not unmute while an ad is showing (the ad-blocker keeps it muted).
    expect(script, contains("classList.contains('ad-showing')"));
    // The real unmute button click must stay scoped to the active player, so a
    // muted feed preview's button can't be clicked by mistake.
    expect(script, contains("player.querySelector('.ytp-unmute-widget button"));
    // An already-audible video must be left untouched (no volume override).
    expect(script, contains('if (!main.muted && main.volume > 0) return { audible: true };'));
  });

  test('ad-blocker only re-mutes mutes it applied itself', () {
    final script = ContentBlockerJS.adFallbackSkipScript;
    // The volumechange re-mute must be gated on _state.weMuted so the app's
    // unmute of a muted next video is never fought and left stuck muted.
    expect(script, contains('_state.weMuted && !video.muted && _adShowing()'));
    // And it must still apply a fresh mute the moment an ad is seen.
    expect(script, contains('video.muted = true;\n            _state.weMuted = true;'));
  });

  test('ad-blocker un-masks a stuck ad instead of leaving a fake loader',
      () {
    final script = ContentBlockerJS.adFallbackSkipScript;
    // A stuck ad (never resolves / duration never becomes finite) must stop
    // showing the black mask + spinner after the watchdog threshold so the next
    // video isn't covered by a permanent loader.
    expect(script, contains("Date.now() - _adStart > 5000"));
    expect(script, contains('_maskDisabled = true;'));
    expect(script, contains("if (!_maskDisabled) _ensureMask();"));
    // The watchdog re-runs the handler so a late-appearing duration still gets
    // skipped even though the MutationObserver sees no class change.
    expect(script, contains('if (_adShowing()) {\n              _handle();'));
  });

  test('unmute retries while the active video is muted and no ad is showing', () {
    const throttle = Duration(milliseconds: 1200);
    // A playing, muted video with no ad: must attempt (once throttled).
    expect(
      PersistentWebViewState.shouldAttemptUnmute(
        playing: true,
        ended: false,
        muted: true,
        adShowing: false,
        timeSinceLastAttempt: throttle,
        throttle: throttle,
      ),
      isTrue,
    );
    // Not playing / ended: never unmute.
    expect(
      PersistentWebViewState.shouldAttemptUnmute(
        playing: false,
        ended: false,
        muted: true,
        adShowing: false,
        timeSinceLastAttempt: throttle,
        throttle: throttle,
      ),
      isFalse,
    );
    // Already audible: no attempt.
    expect(
      PersistentWebViewState.shouldAttemptUnmute(
        playing: true,
        ended: false,
        muted: false,
        adShowing: false,
        timeSinceLastAttempt: throttle,
        throttle: throttle,
      ),
      isFalse,
    );
    // Muted because an ad is showing: the ad-blocker owns it, do not fight it.
    expect(
      PersistentWebViewState.shouldAttemptUnmute(
        playing: true,
        ended: false,
        muted: true,
        adShowing: true,
        timeSinceLastAttempt: throttle,
        throttle: throttle,
      ),
      isFalse,
    );
    // Re-mute right after a successful attempt is retried once throttled
    // (this is the "all next videos muted until reload" latch fix).
    expect(
      PersistentWebViewState.shouldAttemptUnmute(
        playing: true,
        ended: false,
        muted: true,
        adShowing: false,
        timeSinceLastAttempt: Duration.zero,
        throttle: throttle,
      ),
      isFalse,
    );
  });

  test('stuck-PiP un-stick only fires foregrounded, past grace, throttled', () {
    const grace = Duration(milliseconds: 800);
    const throttle = Duration(seconds: 3);
    // Stuck with no window, foregrounded, past grace, throttle elapsed: fire.
    expect(
      PersistentWebViewState.shouldForceVideoInline(
        pipStuck: true,
        backgrounded: false,
        stuckDuration: grace,
        grace: grace,
        timeSinceLastForce: throttle,
        throttle: throttle,
      ),
      isTrue,
    );
    // Backgrounded: never fire (phantom-PiP keep-alive is intentional).
    expect(
      PersistentWebViewState.shouldForceVideoInline(
        pipStuck: true,
        backgrounded: true,
        stuckDuration: grace,
        grace: grace,
        timeSinceLastForce: throttle,
        throttle: throttle,
      ),
      isFalse,
    );
    // A real PiP window reports pipStuck=false: never fire.
    expect(
      PersistentWebViewState.shouldForceVideoInline(
        pipStuck: false,
        backgrounded: false,
        stuckDuration: grace,
        grace: grace,
        timeSinceLastForce: throttle,
        throttle: throttle,
      ),
      isFalse,
    );
    // Brief stuck state (a legit PiP enter/exit transition): not yet.
    expect(
      PersistentWebViewState.shouldForceVideoInline(
        pipStuck: true,
        backgrounded: false,
        stuckDuration: Duration.zero,
        grace: grace,
        timeSinceLastForce: throttle,
        throttle: throttle,
      ),
      isFalse,
    );
    // Throttle not elapsed: no hammering the webview on every report.
    expect(
      PersistentWebViewState.shouldForceVideoInline(
        pipStuck: true,
        backgrounded: false,
        stuckDuration: grace,
        grace: grace,
        timeSinceLastForce: Duration.zero,
        throttle: throttle,
      ),
      isFalse,
    );
  });
}
