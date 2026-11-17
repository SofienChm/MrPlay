import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay/core/utils/url_utils.dart';
import 'package:mrplay/data/models/models.dart';
import 'package:mrplay/features/browser/web_policy.dart';
import 'package:mrplay/features/player/playback_policy.dart';

void main() {
  group('UrlUtils', () {
    test('extracts YouTube ids from watch and short links', () {
      expect(UrlUtils.youTubeId('https://m.youtube.com/watch?v=abc123&t=4'), 'abc123');
      expect(UrlUtils.youTubeId('https://youtu.be/xyz?si=1'), 'xyz');
      expect(UrlUtils.youTubeId('https://example.com'), isNull);
    });

    test('routes only regular YouTube watch pages to the video tab', () {
      expect(UrlUtils.routesToVideoTab('https://m.youtube.com/watch?v=a'), isTrue);
      expect(UrlUtils.routesToVideoTab('https://music.youtube.com/watch?v=a'), isFalse);
      expect(UrlUtils.routesToVideoTab('https://m.youtube.com/results?q=a'), isFalse);
    });

    test('derives platform names from hosts', () {
      expect(UrlUtils.platformName('m.twitch.tv'), 'Twitch');
      expect(UrlUtils.platformName('www.dailymotion.com'), 'Dailymotion');
      expect(UrlUtils.platformName(''), 'Web');
    });

    test('adds a scheme only when missing', () {
      expect(UrlUtils.withScheme('example.com'), 'https://example.com');
      expect(UrlUtils.withScheme('http://a.b'), 'http://a.b');
    });
  });

  group('Video.fromUrl', () {
    test('builds a YouTube placeholder with thumbnail', () {
      final v = Video.fromUrl('https://m.youtube.com/watch?v=abc')!;
      expect(v.id, 'abc');
      expect(v.thumbnailUrl, contains('abc'));
      expect(v.hasPlaceholderTitle, isTrue);
    });

    test('labels YouTube Music and other hosts', () {
      expect(Video.fromUrl('https://music.youtube.com/watch?v=a')!.platform, 'Music');
      expect(Video.fromUrl('https://m.twitch.tv/videos/1')!.platform, 'Twitch');
      expect(Video.fromUrl('not a url'), isNull);
    });
  });

  group('WebPolicy', () {
    test('matches ad domains and subdomains only', () {
      expect(WebPolicy.isAdDomain('doubleclick.net'), isTrue);
      expect(WebPolicy.isAdDomain('stats.g.doubleclick.net'), isTrue);
      expect(WebPolicy.isAdDomain('youtube.com'), isFalse);
      expect(WebPolicy.isAdDomain('rr1.googlevideo.com'), isFalse);
      expect(WebPolicy.isAdDomain('notdoubleclick.net'), isFalse);
    });

    test('always blocks dangerous schemes', () {
      for (final scheme in ['javascript', 'data', 'blob']) {
        expect(WebPolicy.allowNavigation(scheme: scheme, host: '', blockAdDomains: false), isFalse);
      }
    });

    test('blocks ad domains only while popup blocking is on', () {
      expect(WebPolicy.allowNavigation(scheme: 'https', host: 'popads.net', blockAdDomains: true), isFalse);
      expect(WebPolicy.allowNavigation(scheme: 'https', host: 'popads.net', blockAdDomains: false), isTrue);
      expect(WebPolicy.allowNavigation(scheme: 'https', host: 'm.youtube.com', blockAdDomains: true), isTrue);
    });

    test('refuses blank, ad and flooding popups', () {
      const ok = Duration(seconds: 2);
      expect(WebPolicy.allowPopup(host: '', sinceLastAllowed: ok), isFalse);
      expect(WebPolicy.allowPopup(host: 'exoclick.com', sinceLastAllowed: ok), isFalse);
      expect(WebPolicy.allowPopup(host: 'accounts.google.com', sinceLastAllowed: ok), isTrue);
      expect(
        WebPolicy.allowPopup(host: 'accounts.google.com', sinceLastAllowed: const Duration(milliseconds: 100)),
        isFalse,
      );
    });
  });

  group('PlaybackPolicy', () {
    test('clamps seek targets', () {
      const dur = Duration(seconds: 100);
      expect(PlaybackPolicy.clampSeek(const Duration(seconds: -5), dur), Duration.zero);
      expect(PlaybackPolicy.clampSeek(const Duration(seconds: 500), dur), dur);
      expect(PlaybackPolicy.clampSeek(const Duration(seconds: 500), Duration.zero), const Duration(seconds: 500));
    });

    test('unmutes only a playing muted video without ad, throttled', () {
      bool unmute({bool playing = true, bool muted = true, bool ad = false, int sinceMs = 1000}) =>
          PlaybackPolicy.shouldUnmute(
            playing: playing,
            ended: false,
            muted: muted,
            adShowing: ad,
            sinceLastAttempt: Duration(milliseconds: sinceMs),
          );
      expect(unmute(), isTrue);
      expect(unmute(playing: false), isFalse);
      expect(unmute(muted: false), isFalse);
      expect(unmute(ad: true), isFalse);
      expect(unmute(sinceMs: 100), isFalse);
    });

    test('holds the webview only for an unexpected background stop', () {
      bool hold({bool userPaused = false, bool music = false, bool bg = true, bool ended = false}) =>
          PlaybackPolicy.shouldHoldWebView(
            wasPlaying: true,
            playing: false,
            ended: ended,
            backgrounded: bg,
            backgroundAudio: true,
            isMusic: music,
            userPaused: userPaused,
            systemPaused: false,
            handoffPending: false,
          );
      expect(hold(), isTrue);
      expect(hold(userPaused: true), isFalse);
      expect(hold(music: true), isFalse);
      expect(hold(bg: false), isFalse);
      expect(hold(ended: true), isFalse);
    });

    test('forces inline only after the grace period in the foreground', () {
      bool force({bool bg = false, int stuckMs = 1000, int sinceMs = 5000}) => PlaybackPolicy.shouldForceInline(
            pipStuck: true,
            backgrounded: bg,
            stuckFor: Duration(milliseconds: stuckMs),
            sinceLastForce: Duration(milliseconds: sinceMs),
          );
      expect(force(), isTrue);
      expect(force(bg: true), isFalse);
      expect(force(stuckMs: 100), isFalse);
      expect(force(sinceMs: 100), isFalse);
    });

    test('an ad ending is not the video ending', () {
      expect(PlaybackPolicy.isRealEnd(ended: true, adShowing: true), isFalse);
      expect(PlaybackPolicy.isRealEnd(ended: true, adShowing: false), isTrue);
    });
  });
}
