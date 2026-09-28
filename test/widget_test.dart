import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:hive/hive.dart';
import 'package:mrplay/app.dart';
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
}
