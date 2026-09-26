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
}
