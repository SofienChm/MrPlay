# MrPlay - Complete Source Code Dump

This document contains the full project structure and every source file of the MrPlay Flutter app (branch `v2`). It is intended to be handed to another AI for review/analysis. Updated to include the generic content blocker, auto-PiP on background, mic permission fix, and the native iOS features (Home Screen widget, Spotlight, Share Extension).

---

## 1. Project Overview

MrPlay is a multi-platform video/content hub iOS app built with Flutter. It provides:

- A hub screen with a grid of content platforms (YouTube, Music, Twitch, Instagram, etc.).
- A persistent `flutter_inappwebview` WebView that stays alive across navigation.
- Native picture-in-picture (PiP) playback triggered from the WebView via JavaScript.
- Background audio keep-alive (plays a silent looped audio asset while WebView audio plays).
- A mini player / full player overlay controlled by a Riverpod `PlayerNotifier`.
- Favorites (Hive), Settings (SharedPreferences), ad banner (Google Mobile Ads).
- A **generic content blocker** (`lib/core/constants/content_blocker_js.dart`) injected into every page, plus YouTube JavaScript for search SPA intercept, PiP shelter, and visibility keep-alive.
- **Auto-enter PiP when the app backgrounds** via `didChangeAppLifecycleState`.
- Native iOS features: Home Screen widget (`home_widget`), Spotlight search indexing (`CoreSpotlight`), and a Share Extension (`receive_sharing_intent`).
- Deep links through the registered `mrplay://` URL scheme.
- Microphone purpose string kept in `Info.plist` (SDK binaries reference mic APIs so Apple requires the string; the app itself never requests mic access).

## 2. State Management & Data Flow

- **Riverpod** (`flutter_riverpod`) via `NotifierProvider<PlayerNotifier, PlayerState>` in `lib/providers/player_provider.dart`.
- `PlayerState` holds `currentVideo`, `isPlaying`, `isMinimized`, `position`, `duration`.
- `PlayerNotifier.play(video)` also records the video to recent history (`RecentActivityService`, which drives the Home widget) and indexes it in Spotlight (`SpotlightService`).
- The WebView posts video info/state through JS handlers `playerInfo` and `videoState` (registered in `PersistentWebViewState._onWebViewCreated`).
- `PersistentWebViewState.controlVideo('play'|'pause'|'seek', ...)` drives the WebView from the Flutter UI.
- `MrPlayApp.webViewKey` (a `GlobalKey<PersistentWebViewState>`) is used by pages and players to call `loadUrl`, `controlVideo`, and `enterPiP`.
- Widget tree (see `lib/app.dart`): `HubPage` at the base, `PersistentWebView` on top, `PersistentPlayerShell` (mini/full player) above that, and a banner ad slot pinned near the bottom.
- `_MrPlayAppState.initState` wires native integrations: Spotlight open handler, share-link handler, and `HomeWidget.widgetClicked` / `initiallyLaunchedFromHomeWidget` (all deep-link into the WebView via `loadUrl`).
- All native features share the App Group `group.com.mrplay.shared`.

## 3. Directory Tree (source-relevant)

````
mrplay/
|-- lib/
|   |-- main.dart                     # App entry: audio session, MobileAds, Hive init
|   |-- ad_config.dart                # Banner ad unit IDs (test vs prod)
|   |-- app.dart                      # MrPlayApp + static webViewKey + native integrations
|   |-- core/
|   |   |-- constants/
|   |   |   |-- app_constants.dart    # App name/version
|   |   |   |-- platform_constants.dart # 20 platforms (name/url/icon/category/color)
|   |   |   |-- youtube_js.dart       # Injected JS: visibility keep-alive, SPA search + PiP shelter, app-banner removal
|   |   |   `-- content_blocker_js.dart # Generic content blocker (all sites): blocked hosts, selectors, MutationObserver, skip button
|   |   `-- theme/
|   |       |-- app_colors.dart       # Color palette + per-platform brand colors
|   |       `-- app_theme.dart        # Light/dark ThemeData (Poppins)
|   |-- data/
|   |   |-- models/
|   |   |   |-- favorite_video.dart   # Hive @HiveObject model (typeId 0)
|   |   |   |-- favorite_video.g.dart # Generated Hive adapter
|   |   |   `-- platform_model.dart   # Platform metadata model
|   |   `-- repositories/
|   |       |-- favorites_repository.dart # Hive box CRUD
|   |       `-- settings_repository.dart  # SharedPreferences (theme, default platform)
|   |-- models/
|   |   `-- video.dart                # Plain Video model used by the player
|   |-- presentation/
|   |   |-- pages/
|   |   |   |-- hub_page.dart         # Main screen: gradient, search, platform grid
|   |   |   |-- search_page.dart      # Search overlay w/ per-platform query builders
|   |   |   |-- favorites_page.dart   # Favorites list (Hive)
|   |   |   `-- settings_page.dart    # Theme, default platform, clear cache, links
|   |   |-- router/
|   |   |   `-- app_router.dart       # Named routes (unused by current Stack layout)
|   |   `-- widgets/
|   |       |-- error_widget.dart     # CustomErrorWidget
|   |       |-- loading_indicator.dart# Shimmer skeleton
|   |       |-- platform_card.dart    # Tappable grid card with scale animation
|   |       `-- persistent_webview.dart # The persistent InAppWebView + PiP + content blocker injection
|   |-- providers/
|   |   `-- player_provider.dart      # PlayerState + PlayerNotifier (Riverpod) + recent/spotlight hooks
|   |-- services/
|   |   |-- background_audio_keep_alive.dart # Silent looping audio player
|   |   |-- recent_activity_service.dart     # Recent history -> widget data (App Group + SharedPreferences)
|   |   |-- spotlight_service.dart           # CoreSpotlight indexing via platform channel
|   |   `-- share_link_handler.dart          # receive_sharing_intent -> WebView
|   `-- widgets/
|       |-- full_player.dart          # Full-screen player; swipe-down minimizes + enters PiP
|       |-- mini_player.dart          # Bottom mini bar; swipe-down enters PiP, tap expands
|       |-- persistent_player_shell.dart # AnimatedSwitcher between mini and full
|       `-- unified_banner_ad_slot.dart # Google banner ad with dismiss/reappear
|-- ios/
|   |-- Runner/
|   |   |-- AppDelegate.swift         # Native: AVAudioSession + CoreSpotlight channel
|   |   `-- Info.plist                # UIBackgroundModes audio, GAD app id, mic purpose, URL schemes, AppGroupId
|   `-- HomeWidgetExtension/          # WidgetKit extension source (manual Xcode target; see NATIVE_FEATURES.md)
|-- assets/
|   |-- audio/silence.wav             # Silent loop for background audio keep-alive
|   `-- images/logo.png, splash.png
|-- test/widget_test.dart             # Smoke test (renders hub page)
|-- pubspec.yaml
|-- analysis_options.yaml
|-- flutter_native_splash.yaml
|-- codemagic.yaml                    # CI: iOS App Store build + TestFlight
`-- NATIVE_FEATURES.md                # Xcode setup steps for widget + share extension
````

## 4. Key Gesture & Native Behavior

- **Full player**: `_onVerticalDragEnd` in `lib/widgets/full_player.dart` — when a downward swipe is detected (velocity > 500 or drag > 150), it calls `MrPlayApp.webViewKey.currentState?.enterPiP()` before running the minimize slide animation.
- **Mini player**: `_onVerticalDragUpdate`/`_onVerticalDragEnd` in `lib/widgets/mini_player.dart` — downward swipe (velocity > 400 or drag > 150) calls `enterPiP()`; the bar remains minimized. Tap still expands.
- **Auto-PiP on background**: `didChangeAppLifecycleState` in `lib/presentation/widgets/persistent_webview.dart` — on `AppLifecycleState.paused` it re-asserts the audio session and calls `enterPiP()`.
- **`PersistentWebViewState.enterPiP()`** in `lib/presentation/widgets/persistent_webview.dart` runs enter-only PiP JS (idempotent): uses `requestPictureInPicture()` (with `document.pictureInPictureElement` guard) or `webkitSetPresentationMode('picture-in-picture')` on iOS. `_togglePiP()` remains for the overlay button.
- **Content blocker**: `ContentBlockerJS.genericAdBlockerScript` is injected as an `initialUserScript` (AT_DOCUMENT_START) for every page load, before the visibility keep-alive script.
- **Widget / Spotlight / Share data flow**: every `play()` writes to `RecentActivityService` (SharedPreferences + App Group JSON under key `recent`) and calls `SpotlightService.index`; widget taps and Spotlight results deep-link back via `mrplay://open?url=...&homeWidget`.

---

## 5. Configuration Files

### pubspec.yaml
```yaml
name: mrplay
description: "Multi-platform video hub with background audio"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6
  flutter_inappwebview: ^6.1.5
  audio_session: ^0.1.21
  shared_preferences: ^2.2.2
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  dio: ^5.4.0
  json_annotation: ^4.8.1
  flutter_svg: ^2.0.9
  url_launcher: ^6.2.4
  share_plus: ^7.2.2
  path_provider: ^2.1.2
  google_fonts: ^6.1.0
  shimmer: ^3.0.0
  flutter_riverpod: ^2.5.1
  cached_network_image: ^3.3.1
  google_mobile_ads: ^5.1.0
  audioplayers: ^6.1.0
  home_widget: 0.7.0+1
  receive_sharing_intent: ^1.7.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  build_runner: ^2.4.8
  json_serializable: ^6.7.1
  hive_generator: ^2.0.1
  flutter_native_splash: ^2.4.0

flutter:
  uses-material-design: true
  assets:
    - assets/icons/
    - assets/images/
    - assets/audio/
```

### analysis_options.yaml
```yaml
# This file configures the analyzer, which statically analyzes Dart code to
# check for errors, warnings, and lints.
#
# The issues identified by the analyzer are surfaced in the UI of Dart-enabled
# IDEs (https://dart.dev/tools#ides-and-editors). The analyzer can also be
# invoked from the command line by running `flutter analyze`.

# The following line activates a set of recommended lints for Flutter apps,
# packages, and plugins designed to encourage good coding practices.
include: package:flutter_lints/flutter.yaml

linter:
  # The lint rules applied to this project can be customized in the
  # section below to disable rules from the `package:flutter_lints/flutter.yaml`
  # included above or to enable additional rules. A list of all available lints
  # and their documentation is published at https://dart.dev/lints.
  #
  # Instead of disabling a lint rule for the entire project in the
  # section below, it can also be suppressed for a single line of code
  # or a specific dart file by using the `// ignore: name_of_lint` and
  # `// ignore_for_file: name_of_lint` syntax on the line or in the file
  # producing the lint.
  rules:
    # avoid_print: false  # Uncomment to disable the `avoid_print` rule
    # prefer_single_quotes: true  # Uncomment to enable the `prefer_single_quotes` rule

# Additional information about this file can be found at
# https://dart.dev/guides/language/analysis-options
```

### flutter_native_splash.yaml
```yaml
flutter_native_splash:
  color: "#0F0F0F"
  image: assets/images/splash.png
  branding: assets/images/logo.png
  android_12:
    color: "#0F0F0F"
    image: assets/images/splash.png
```

### codemagic.yaml
```yaml
workflows:
  ios-build:
    name: iOS Build
    max_build_duration: 60
    instance_type: mac_mini_m2
    integrations:
      app_store_connect: Codemagic admin
    environment:
      flutter: stable
      xcode: latest
      cocoapods: default
      vars:
        FLUTTER_DISABLE_SPM: "true"
      groups:
        - mrplay_prod
    triggering:
      events:
        - push
      branch_patterns:
        - pattern: never
          include: false
    scripts:
      - name: Disable Swift Package Manager Engine Globally
        script: |
          flutter config --no-enable-swift-package-manager
      - name: Get Flutter packages
        script: |
          flutter pub get
      - name: Install CocoaPods
        script: |
          cd ios
          pod install --repo-update
          cd ..
      - name: Initialize keychain
        script: keychain initialize
      - name: Fetch signing files from App Store Connect
        script: |
          app-store-connect fetch-signing-files com.mrplay.app \
            --type IOS_APP_STORE \
            --create \
            --certificate-key "$CERTIFICATE_PRIVATE_KEY"
      - name: Add certificates to keychain
        script: keychain add-certificates
      - name: Apply provisioning profiles
        script: xcode-project use-profiles
      - name: Build IPA
        script: |
          flutter build ipa --release --export-method app-store --build-number $BUILD_NUMBER
    artifacts:
      - build/ios/ipa/*.ipa
    publishing:
      app_store_connect:
        auth: integration
        submit_to_testflight: true
```

## 6. Native iOS Files

### ios/Runner/Info.plist
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
	<dict>
		<key>CFBundleDevelopmentRegion</key>
		<string>$(DEVELOPMENT_LANGUAGE)</string>
		<key>CFBundleDisplayName</key>
		<string>Mrplay</string>
		<key>CFBundleExecutable</key>
		<string>$(EXECUTABLE_NAME)</string>
		<key>CFBundleIdentifier</key>
		<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
		<key>CFBundleInfoDictionaryVersion</key>
		<string>6.0</string>
		<key>CFBundleName</key>
		<string>mrplay</string>
		<key>CFBundlePackageType</key>
		<string>APPL</string>
		<key>CFBundleShortVersionString</key>
		<string>$(FLUTTER_BUILD_NAME)</string>
		<key>CFBundleSignature</key>
		<string>????</string>
		<key>CFBundleVersion</key>
		<string>$(FLUTTER_BUILD_NUMBER)</string>
		<key>LSRequiresIPhoneOS</key>
		<true/>
		<key>UILaunchStoryboardName</key>
		<string>LaunchScreen</string>
		<key>UIMainStoryboardFile</key>
		<string>Main</string>
		<key>UISupportedInterfaceOrientations</key>
		<array>
			<string>UIInterfaceOrientationPortrait</string>
			<string>UIInterfaceOrientationLandscapeLeft</string>
			<string>UIInterfaceOrientationLandscapeRight</string>
		</array>
		<key>UISupportedInterfaceOrientations~ipad</key>
		<array>
			<string>UIInterfaceOrientationPortrait</string>
			<string>UIInterfaceOrientationPortraitUpsideDown</string>
			<string>UIInterfaceOrientationLandscapeLeft</string>
			<string>UIInterfaceOrientationLandscapeRight</string>
		</array>
		<key>CADisableMinimumFrameDurationOnPhone</key>
		<true/>
		<key>UIApplicationSupportsIndirectInputEvents</key>
		<true/>
		<key>UIBackgroundModes</key>
		<array>
			<string>audio</string>
		</array>
		<key>UIStatusBarHidden</key>
		<false/>
	<key>GADApplicationIdentifier</key>
	<string>ca-app-pub-3940256099942544~1458002511</string>
	<key>AppGroupId</key>
	<string>group.com.mrplay.shared</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Microphone access is used by web content you open in MrPlay for audio recording and voice features.</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLName</key>
			<string>com.mrplay.app</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>mrplay</string>
			</array>
		</dict>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

### ios/Runner/AppDelegate.swift
```swift
import UIKit
import Flutter
import AVFoundation
import WebKit
import CoreSpotlight
import UniformTypeIdentifiers

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var spotlightChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: .duckOthers)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("MrPlay: AVAudioSession error: \(error)")
    }

    setupSpotlightChannel()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupSpotlightChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "com.mrplay/spotlight", binaryMessenger: controller.binaryMessenger)
    spotlightChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "index":
        if let args = call.arguments as? [String: Any],
           let title = args["title"] as? String,
           let url = args["url"] as? String {
          self.indexSpotlight(title: title, subtitle: args["subtitle"] as? String ?? "", url: url)
        }
        result(nil)
      case "remove":
        if let url = (call.arguments as? [String: Any])?["url"] as? String {
          self.removeSpotlight(url: url)
        }
        result(nil)
      case "clear":
        self.clearSpotlight()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == CSSearchableItemActionType,
       let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
      let url = identifier.hasPrefix("mrplay:") ? String(identifier.dropFirst("mrplay:".count)) : identifier
      spotlightChannel?.invokeMethod("open", arguments: url)
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  private func indexSpotlight(title: String, subtitle: String, url: String) {
    let attributeSet: CSSearchableItemAttributeSet
    if #available(iOS 14.0, *) {
      attributeSet = CSSearchableItemAttributeSet(contentType: UTType.movie)
    } else {
      attributeSet = CSSearchableItemAttributeSet(itemContentType: "public.movie")
    }
    attributeSet.title = title
    attributeSet.contentDescription = subtitle
    let item = CSSearchableItem(
      uniqueIdentifier: "mrplay:\(url)",
      domainIdentifier: "mrplay.videos",
      attributeSet: attributeSet
    )
    item.expirationDate = Date(timeIntervalSinceNow: 60 * 60 * 24 * 30)
    CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
  }

  private func removeSpotlight(url: String) {
    CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ["mrplay:\(url)"]) { _ in }
  }

  private func clearSpotlight() {
    CSSearchableIndex.default().deleteAllSearchableItems { _ in }
  }
}
```

### ios/HomeWidgetExtension/HomeWidgetExtension.swift
```swift
import WidgetKit
import SwiftUI

private let widgetGroupId = "group.com.mrplay.shared"

struct RecentEntry: TimelineEntry {
  let date: Date
  let videos: [[String: String]]
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> RecentEntry {
    RecentEntry(date: Date(), videos: [])
  }

  func getSnapshot(in context: Context, completion: @escaping (RecentEntry) -> Void) {
    completion(makeEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    completion(Timeline(entries: [makeEntry()], policy: .atEnd))
  }

  private func makeEntry() -> RecentEntry {
    var videos: [[String: String]] = []
    if let raw = UserDefaults(suiteName: widgetGroupId)?.string(forKey: "recent"),
       let data = raw.data(using: .utf8),
       let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
      videos = Array(decoded.prefix(3))
    }
    return RecentEntry(date: Date(), videos: videos)
  }
}

struct MrPlayRecentWidgetView: View {
  let entry: Provider.Entry

  var body: some View {
    content
      .widgetURL(fallbackUrl)
      .widgetBackground()
  }

  @ViewBuilder
  private var content: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Image(systemName: "play.rectangle.fill")
          .font(.caption)
        Text("MrPlay")
          .font(.caption)
          .bold()
      }
      .foregroundColor(.secondary)

      if entry.videos.isEmpty {
        Spacer()
        Text("Watch a video to see it here")
          .font(.caption2)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
        Spacer()
      } else {
        ForEach(Array(entry.videos.enumerated()), id: \.offset) { _, video in
          HStack(spacing: 6) {
            Image(systemName: "play.circle.fill")
              .font(.system(size: 12))
              .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 1) {
              Text(video["title"] ?? "")
                .font(.caption)
                .lineLimit(1)
              Text(video["platform"] ?? "")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
          }
          .foregroundColor(.primary)
          .widgetURL(url(for: video))
        }
        Spacer(minLength: 0)
      }
    }
    .padding(8)
  }

  private var fallbackUrl: URL? {
    guard let first = entry.videos.first else { return nil }
    return url(for: first)
  }

  private func url(for video: [String: String]) -> URL? {
    guard let urlString = video["url"]?
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
    return URL(string: "mrplay://open?url=\(urlString)&homeWidget")
  }
}

@main
struct MrPlayRecentWidget: Widget {
  let kind: String = "MrPlayRecentWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      MrPlayRecentWidgetView(entry: entry)
    }
    .configurationDisplayName("MrPlay Recent")
    .description("Your recently watched videos, one tap away.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private extension View {
  @ViewBuilder
  func widgetBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) {
        Color.black
      }
    } else {
      background(Color.black)
    }
  }
}
```

### ios/HomeWidgetExtension/Info.plist
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>MrPlay Recent</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>AppGroupId</key>
	<string>group.com.mrplay.shared</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
```

## 7. Dart & Flutter Source Files

### lib/main.dart
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_session/audio_session.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'app.dart';
import 'data/models/favorite_video.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionMode: AVAudioSessionMode.moviePlayback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
  ));

  await MobileAds.instance.initialize();

  await Hive.initFlutter();
  Hive.registerAdapter(FavoriteVideoAdapter());
  runApp(const ProviderScope(child: MrPlayApp()));
}
```

### lib/ad_config.dart
```dart
import 'package:flutter/foundation.dart';

class AdConfig {
  AdConfig._();

  static const String _testBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _prodBannerAdUnitId =
      'ca-app-pub-2351054385499645/9979835900';

  static String get bannerAdUnitId {
    return kDebugMode ? _testBannerAdUnitId : _prodBannerAdUnitId;
  }
}
```

### lib/app.dart
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'core/theme/app_theme.dart';
import 'presentation/pages/hub_page.dart';
import 'presentation/widgets/persistent_webview.dart';
import 'services/share_link_handler.dart';
import 'services/spotlight_service.dart';
import 'widgets/persistent_player_shell.dart';
import 'widgets/unified_banner_ad_slot.dart';

class MrPlayApp extends StatefulWidget {
  const MrPlayApp({super.key});

  static final GlobalKey<PersistentWebViewState> webViewKey = GlobalKey();
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);

  @override
  State<MrPlayApp> createState() => _MrPlayAppState();
}

class _MrPlayAppState extends State<MrPlayApp> {
  @override
  void initState() {
    super.initState();
    _initNativeIntegrations();
  }

  void _initNativeIntegrations() {
    SpotlightService.setOpenHandler(_openExternalUrl);
    ShareLinkHandler.instance.init(_openExternalUrl);
    HomeWidget.widgetClicked.listen(_openFromWidget);
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_openFromWidget);
  }

  void _openExternalUrl(String url) {
    MrPlayApp.webViewKey.currentState?.loadUrl(url);
  }

  void _openFromWidget(Uri? uri) {
    if (uri == null) return;
    final url = uri.queryParameters['url'];
    if (url != null && url.isNotEmpty) {
      MrPlayApp.webViewKey.currentState?.loadUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: MrPlayApp.themeModeNotifier,
      builder: (context, themeMode, _) {
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        );
        return MaterialApp(
          title: 'MrPlay',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: Scaffold(
            body: Stack(
              children: [
                const HubPage(),
                Positioned.fill(
                  child: SafeArea(
                    child: PersistentWebView(key: MrPlayApp.webViewKey),
                  ),
                ),
                const PersistentPlayerShell(),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 80,
                  child: UnifiedBannerAdSlot(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

### lib/core/constants/app_constants.dart
```dart
class AppConstants {
  static const String appName = 'MrPlay';
  static const String appVersion = '1.0.0';
  static const String appSubtitle = 'Your Video Hub';

  // Replace with the real numeric Apple ID once the app is registered.
  static const String appStoreAppId = '000000000';
  static const String appStoreUrl = 'https://apps.apple.com/app/id$appStoreAppId';
}
```

### lib/core/constants/platform_constants.dart
```dart
import '../theme/app_colors.dart';
import '../../data/models/platform_model.dart';

class PlatformConstants {
  static final List<PlatformModel> platforms = [
    PlatformModel(name: 'YouTube', url: 'https://m.youtube.com', icon: 'youtube', category: 'video', color: AppColors.youtube),
    PlatformModel(name: 'Music', url: 'https://music.youtube.com', icon: 'music', category: 'music', color: AppColors.music),
    PlatformModel(name: 'Twitch', url: 'https://m.twitch.tv', icon: 'twitch', category: 'video', color: AppColors.twitch),
    PlatformModel(name: 'Rumble', url: 'https://rumble.com', icon: 'rumble', category: 'video', color: AppColors.rumble),
    PlatformModel(name: 'Duolingo', url: 'https://duolingo.com', icon: 'duolingo', category: 'education', color: AppColors.duolingo),
    PlatformModel(name: 'Busuu', url: 'https://busuu.com', icon: 'busuu', category: 'education', color: AppColors.busuu),
    PlatformModel(name: 'Babbel', url: 'https://babbel.com', icon: 'babbel', category: 'education', color: AppColors.babbel),
    PlatformModel(name: 'Memrise', url: 'https://memrise.com', icon: 'memrise', category: 'education', color: AppColors.memrise),
    PlatformModel(name: 'Mondly', url: 'https://mondly.com', icon: 'mondly', category: 'education', color: AppColors.mondly),
    PlatformModel(name: 'Instagram', url: 'https://instagram.com', icon: 'instagram', category: 'social', color: AppColors.instagram),
    PlatformModel(name: 'Reddit', url: 'https://reddit.com', icon: 'reddit', category: 'social', color: AppColors.reddit),
    PlatformModel(name: 'Facebook', url: 'https://facebook.com', icon: 'facebook', category: 'social', color: AppColors.facebook),
    PlatformModel(name: 'X', url: 'https://x.com', icon: 'x', category: 'social', color: AppColors.x),
    PlatformModel(name: 'Disney+', url: 'https://disneyplus.com', icon: 'disney', category: 'streaming', color: AppColors.disney),
    PlatformModel(name: 'HBO Max', url: 'https://max.com', icon: 'hbo', category: 'streaming', color: AppColors.hbo),
    PlatformModel(name: 'Prime Video', url: 'https://primevideo.com', icon: 'prime', category: 'streaming', color: AppColors.prime),
    PlatformModel(name: 'Pinterest', url: 'https://pinterest.com', icon: 'pinterest', category: 'social', color: AppColors.pinterest),
    PlatformModel(name: 'Quora', url: 'https://quora.com', icon: 'quora', category: 'social', color: AppColors.quora),
    PlatformModel(name: '9gag', url: 'https://9gag.com', icon: '9gag', category: 'social', color: AppColors.gag),
    PlatformModel(name: 'iFunny', url: 'https://ifunny.co', icon: 'ifunny', category: 'social', color: AppColors.ifunny),
  ];
}
```

### lib/core/constants/youtube_js.dart
```dart
class YouTubeJS {
  static const String visibilityKeepAliveScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1) return;
      try {
        Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: false });
        Object.defineProperty(document, 'webkitHidden', { get: function() { return false; }, configurable: false });
        Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: false });
        Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; }, configurable: false });

        document.hasFocus = function() { return true; };

        var origAdd = EventTarget.prototype.addEventListener;
        EventTarget.prototype.addEventListener = function(type, fn, opts) {
          if (['visibilitychange', 'webkitvisibilitychange', 'pagehide', 'beforeunload', 'blur'].indexOf(type) >= 0) {
            return;
          }
          return origAdd.call(this, type, fn, opts);
        };

        var lastReport = 0;
        function prepareVideo(v) {
          v.setAttribute('playsinline', 'true');
          v.setAttribute('webkit-playsinline', 'true');
          v.setAttribute('pip', 'true');
          v.style.objectFit = 'contain';

          v.addEventListener('play', reportState);
          v.addEventListener('pause', reportState);
          v.addEventListener('ended', reportState);
          v.addEventListener('durationchange', reportState);
          v.addEventListener('timeupdate', function() {
            var now = Date.now();
            if (now - lastReport < 250) return;
            lastReport = now;
            reportState.call(this);
          });

          v.addEventListener('playing', function() {
            if (window.__mrplayReleaseSheltered) window.__mrplayReleaseSheltered(this);
          });
        }

        function reportState() {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler('videoState', {
              playing: !this.paused && !this.ended,
              position: this.currentTime || 0,
              duration: this.duration || 0,
              ended: !!this.ended
            });
          }
        }

        document.querySelectorAll('video').forEach(prepareVideo);
        new MutationObserver(function(mutations) {
          mutations.forEach(function(m) {
            m.addedNodes.forEach(function(n) {
              if (n.nodeName === 'VIDEO') prepareVideo(n);
            });
          });
        }).observe(document.documentElement, { childList: true, subtree: true });
      } catch (e) {}
    })();
  ''';

  static const String searchSpaScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1) return;

      var sheltered = null;
      var shelterEl = null;

      function ensureShelter() {
        if (!shelterEl) {
          shelterEl = document.createElement('div');
          shelterEl.id = '__mrplay_shelter';
          shelterEl.style.cssText = 'position:fixed;left:-10000px;top:0;width:1px;height:1px;opacity:0;pointer-events:none;overflow:hidden;';
          document.body.appendChild(shelterEl);
        }
        return shelterEl;
      }

      function inPip(v) {
        if (v && typeof v.webkitPresentationMode !== 'undefined' && v.webkitPresentationMode === 'picture-in-picture') return true;
        if (typeof document.pictureInPictureElement !== 'undefined' && document.pictureInPictureElement) return true;
        return false;
      }

      function isActive(v) {
        return !!v && ((!v.paused && !v.ended) || inPip(v));
      }

      function shelterPlayingVideo() {
        var v = document.querySelector('video');
        if (!v || v === sheltered) return;
        if (!isActive(v)) return;
        if (sheltered) {
          try { sheltered.remove(); } catch (e) {}
        }
        ensureShelter().appendChild(v);
        sheltered = v;
      }

      window.__mrplayReleaseSheltered = function(newVideo) {
        if (!sheltered) return;
        if (newVideo && newVideo === sheltered) return;
        // Only release the sheltered video when a real watch-page player starts
        // playing a new video (search hover previews must not close PiP).
        if (newVideo && !newVideo.closest('ytd-watch-flexy, ytd-watch, ytm-watch, #movie_player')) return;
        try { sheltered.remove(); } catch (e) {}
        sheltered = null;
      };

      // Search: keep the playing/PiP video alive while navigating to results.
      // Do NOT preventDefault - let YouTube's own router drive the navigation.
      document.addEventListener('submit', function(e) {
        var form = e.target;
        if (!form || !form.action) return;
        if (String(form.action).indexOf('/results') === -1) return;
        shelterPlayingVideo();
      }, true);

      // Back/forward navigation: shelter the video before YouTube tears down
      // the watch page, so PiP / background audio survives.
      window.addEventListener('popstate', function() {
        shelterPlayingVideo();
      }, true);
    })();
  ''';

  static const String appBannerRemoverScript = '''
    (function() {
      if (location.hostname.indexOf('youtube.com') === -1) return;
      var selectors = [
        '.ytp-open-app-button',
        'ytd-open-in-app-banner',
        'ytm-open-in-app-banner',
        'ytd-mobile-app-banner-renderer',
        'ytm-mobile-app-banner',
        'ytd-guide-entry-point',
        '#open-in-app',
        '.open-in-app'
      ];

      function removeAppUI() {
        document.querySelectorAll('a[href^="youtube://"], a[href^="vnd.youtube://"], a[href^="yt://"]').forEach(function(a) {
          a.remove();
        });
        selectors.forEach(function(sel) {
          document.querySelectorAll(sel).forEach(function(el) {
            el.remove();
          });
        });
        document.querySelectorAll('button, a, ytd-button-renderer, ytm-button-renderer').forEach(function(el) {
          var t = (el.textContent || '').toLowerCase();
          if (t.indexOf('open in the youtube app') > -1 || t.indexOf('open in youtube app') > -1 || t.indexOf('watch in the youtube app') > -1 || t.indexOf('get the youtube app') > -1) {
            el.remove();
          }
        });
      }

      removeAppUI();
      new MutationObserver(removeAppUI).observe(document.documentElement, { childList: true, subtree: true });
    })();
  ''';
}
```

### lib/core/constants/content_blocker_js.dart
```dart
class ContentBlockerJS {
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
      new MutationObserver(function() {
        requestAnimationFrame(blockAds);
      }).observe(document.documentElement, { childList: true, subtree: true });

      setInterval(function() {
        var btn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern');
        if (btn) btn.click();
      }, 500);
    })();
  ''';
}
```

### lib/core/theme/app_colors.dart
```dart
import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF2196F3);
  static const Color secondary = Color(0xFF4CAF50);
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color error = Color(0xFFF44336);
  static const Color border = Color(0xFF2C2C2C);

  static const Color youtube = Color(0xFFFF0000);
  static const Color music = Color(0xFFFF0000);
  static const Color twitch = Color(0xFF9146FF);
  static const Color rumble = Color(0xFF85C742);
  static const Color duolingo = Color(0xFF58CC02);
  static const Color busuu = Color(0xFFFF6B35);
  static const Color babbel = Color(0xFFE5004D);
  static const Color memrise = Color(0xFFEE5D6C);
  static const Color mondly = Color(0xFF0066FF);
  static const Color instagram = Color(0xFFE1306C);
  static const Color reddit = Color(0xFFFF4500);
  static const Color facebook = Color(0xFF1877F2);
  static const Color x = Color(0xFF000000);
  static const Color disney = Color(0xFF0063E5);
  static const Color hbo = Color(0xFFB535F6);
  static const Color prime = Color(0xFF00A8E1);
  static const Color pinterest = Color(0xFFE60023);
  static const Color quora = Color(0xFFA82400);
  static const Color gag = Color(0xFF00CC00);
  static const Color ifunny = Color(0xFF2FB5E8);

  static const Color hubGradientStart = Color(0xFF1A237E);
  static const Color hubGradientEnd = Color(0xFF004D40);
}
```

### lib/core/theme/app_theme.dart
```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: GoogleFonts.poppinsTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: const Color(0xFF121212),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF121212),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
```

### lib/data/models/favorite_video.dart
```dart
import 'package:hive/hive.dart';

part 'favorite_video.g.dart';

@HiveType(typeId: 0)
class FavoriteVideo extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String channel;

  @HiveField(3)
  final String thumbnailUrl;

  @HiveField(4)
  final String platformUrl;

  @HiveField(5)
  final DateTime addedAt;

  FavoriteVideo({
    required this.id,
    required this.title,
    required this.channel,
    required this.thumbnailUrl,
    required this.platformUrl,
    required this.addedAt,
  });
}
```

### lib/data/models/favorite_video.g.dart
```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_video.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FavoriteVideoAdapter extends TypeAdapter<FavoriteVideo> {
  @override
  final int typeId = 0;

  @override
  FavoriteVideo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FavoriteVideo(
      id: fields[0] as String,
      title: fields[1] as String,
      channel: fields[2] as String,
      thumbnailUrl: fields[3] as String,
      platformUrl: fields[4] as String,
      addedAt: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, FavoriteVideo obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.channel)
      ..writeByte(3)
      ..write(obj.thumbnailUrl)
      ..writeByte(4)
      ..write(obj.platformUrl)
      ..writeByte(5)
      ..write(obj.addedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteVideoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
```

### lib/data/models/platform_model.dart
```dart
class PlatformModel {
  final String name;
  final String url;
  final String icon;
  final String category;
  final dynamic color;

  const PlatformModel({
    required this.name,
    required this.url,
    required this.icon,
    required this.category,
    this.color,
  });
}
```

### lib/data/repositories/favorites_repository.dart
```dart
import 'package:hive_flutter/hive_flutter.dart';
import '../models/favorite_video.dart';

class FavoritesRepository {
  static const String _boxName = 'favorites';
  static Box<FavoriteVideo>? _box;

  static Future<Box<FavoriteVideo>> get box async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox<FavoriteVideo>(_boxName);
    return _box!;
  }

  static Future<List<FavoriteVideo>> getAll() async {
    final b = await box;
    return b.values.toList().reversed.toList();
  }

  static Future<void> add(FavoriteVideo video) async {
    final b = await box;
    await b.put(video.id, video);
  }

  static Future<void> remove(String id) async {
    final b = await box;
    await b.delete(id);
  }

  static Future<bool> isFavorite(String id) async {
    final b = await box;
    return b.containsKey(id);
  }

  static Future<void> clear() async {
    final b = await box;
    await b.clear();
  }
}
```

### lib/data/repositories/settings_repository.dart
```dart
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const String _themeKey = 'theme_mode';
  static const String _defaultPlatformKey = 'default_platform';

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static Future<String> getThemeMode() async {
    final prefs = await _prefs;
    return prefs.getString(_themeKey) ?? 'system';
  }

  static Future<void> setThemeMode(String mode) async {
    final prefs = await _prefs;
    await prefs.setString(_themeKey, mode);
  }

  static Future<String> getDefaultPlatform() async {
    final prefs = await _prefs;
    return prefs.getString(_defaultPlatformKey) ?? 'YouTube';
  }

  static Future<void> setDefaultPlatform(String name) async {
    final prefs = await _prefs;
    await prefs.setString(_defaultPlatformKey, name);
  }

  static Future<void> clearCache() async {
    final prefs = await _prefs;
    await prefs.remove(_themeKey);
    await prefs.remove(_defaultPlatformKey);
  }
}
```

### lib/models/video.dart
```dart
class Video {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String videoUrl;
  final String platform;

  const Video({
    required this.id,
    required this.title,
    this.thumbnailUrl = '',
    required this.videoUrl,
    this.platform = '',
  });
}
```

### lib/presentation/pages/favorites_page.dart
```dart
import 'package:flutter/material.dart';
import '../../data/models/favorite_video.dart';
import '../../data/repositories/favorites_repository.dart';
import '../../app.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<FavoriteVideo> _favorites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favorites = await FavoritesRepository.getAll();
    if (mounted) {
      setState(() {
        _favorites = favorites;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFavorite(FavoriteVideo video) async {
    await FavoritesRepository.remove(video.id);
    _loadFavorites();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        actions: [
          if (_favorites.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                await FavoritesRepository.clear();
                _loadFavorites();
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No favorites yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _favorites.length,
                  itemBuilder: (context, index) {
                    final video = _favorites[index];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 120,
                          height: 68,
                          child: video.thumbnailUrl.isNotEmpty
                              ? Image.network(video.thumbnailUrl, fit: BoxFit.cover)
                              : Container(color: Colors.grey, child: const Icon(Icons.play_circle, color: Colors.white)),
                        ),
                      ),
                      title: Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(video.channel, maxLines: 1),
                      trailing: IconButton(
                        icon: const Icon(Icons.favorite, color: Colors.red),
                        onPressed: () => _removeFavorite(video),
                      ),
                      onTap: () {
                        MrPlayApp.webViewKey.currentState?.loadUrl(video.platformUrl);
                      },
                    );
                  },
                ),
    );
  }
}
```

### lib/presentation/pages/hub_page.dart
```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/platform_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/platform_model.dart';
import '../widgets/platform_card.dart';
import '../pages/search_page.dart';
import 'favorites_page.dart';
import 'settings_page.dart';
import '../../app.dart';

class HubPage extends StatefulWidget {
  const HubPage({super.key});

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  final TextEditingController _searchController = TextEditingController();
  List<PlatformModel> _filteredPlatforms = PlatformConstants.platforms;
  bool _showResults = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredPlatforms = PlatformConstants.platforms;
        _showResults = false;
      } else {
        _filteredPlatforms = PlatformConstants.platforms
            .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
        _showResults = true;
      }
    });
  }

  void _onSearchSubmitted(String query) {
    if (query.isEmpty) return;

    final matched = PlatformConstants.platforms
        .where((p) => p.name.toLowerCase() == query.toLowerCase())
        .toList();

    if (matched.isNotEmpty) {
      _onPlatformTap(matched.first);
    } else {
      _launchGoogleSearch(query);
    }
    _searchController.clear();
    setState(() => _showResults = false);
  }

  Future<void> _launchGoogleSearch(String query) async {
    final url = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _onPlatformTap(PlatformModel platform) {
    MrPlayApp.webViewKey.currentState?.loadUrl(platform.url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.hubGradientStart, AppColors.hubGradientEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.search, color: Colors.white),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SearchPage()),
                        );
                      },
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.favorite, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const FavoritesPage()),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SettingsPage()),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'MrPlay',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    onSubmitted: _onSearchSubmitted,
                    decoration: InputDecoration(
                      hintText: 'Search platforms or Google...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _showResults && _filteredPlatforms.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.search_off, size: 64, color: Colors.white38),
                            const SizedBox(height: 16),
                            Text(
                              'No platforms match "${_searchController.text}"',
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Press Enter to search Google',
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _filteredPlatforms.length,
                          itemBuilder: (context, index) {
                            final platform = _filteredPlatforms[index];
                            return PlatformCard(
                              platform: platform,
                              onTap: () => _onPlatformTap(platform),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### lib/presentation/pages/search_page.dart
```dart
import 'package:flutter/material.dart';
import '../../core/constants/platform_constants.dart';
import '../../data/models/platform_model.dart';
import '../../app.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  PlatformModel? _selectedPlatform;

  @override
  void initState() {
    super.initState();
    _selectedPlatform = PlatformConstants.platforms.first;
  }

  void _performSearch() {
    final query = _controller.text.trim();
    if (query.isEmpty || _selectedPlatform == null) return;

    final searchUrl = _getSearchUrl(_selectedPlatform!.url, query);
    MrPlayApp.webViewKey.currentState?.loadUrl(searchUrl);
    Navigator.pop(context);
  }

  String _getSearchUrl(String baseUrl, String query) {
    final uri = Uri.parse(baseUrl);
    final host = uri.host;

    if (host.contains('youtube.com')) {
      return 'https://m.youtube.com/results?search_query=${Uri.encodeComponent(query)}';
    } else if (host.contains('twitch.tv')) {
      return 'https://m.twitch.tv/search?term=${Uri.encodeComponent(query)}';
    } else if (host.contains('reddit.com')) {
      return 'https://www.reddit.com/search/?q=${Uri.encodeComponent(query)}';
    } else if (host.contains('instagram.com')) {
      return 'https://www.instagram.com/explore/search/keyword/?q=${Uri.encodeComponent(query)}';
    } else if (host.contains('pinterest.com')) {
      return 'https://www.pinterest.com/search/pins/?q=${Uri.encodeComponent(query)}';
    }
    return '$baseUrl/search?q=${Uri.encodeComponent(query)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _performSearch(),
                decoration: InputDecoration(
                  hintText: 'Search ${_selectedPlatform?.name ?? ""}...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: PlatformConstants.platforms.length,
                itemBuilder: (context, index) {
                  final platform = PlatformConstants.platforms[index];
                  final isSelected = _selectedPlatform?.name == platform.name;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(platform.name),
                      selected: isSelected,
                      selectedColor: platform.color,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : null,
                        fontSize: 12,
                      ),
                      onSelected: (_) {
                        setState(() => _selectedPlatform = platform);
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Quick search on:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 2,
                ),
                itemCount: PlatformConstants.platforms.length,
                itemBuilder: (context, index) {
                  final platform = PlatformConstants.platforms[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() => _selectedPlatform = platform);
                      _performSearch();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: platform.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: platform.color.withOpacity(0.3)),
                      ),
                      child: Center(
                        child: Text(
                          platform.name,
                          style: TextStyle(
                            color: platform.color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### lib/presentation/pages/settings_page.dart
```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app.dart';
import '../../core/constants/platform_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../data/repositories/settings_repository.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _themeMode = 'system';
  String _defaultPlatform = 'YouTube';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final theme = await SettingsRepository.getThemeMode();
    final platform = await SettingsRepository.getDefaultPlatform();
    if (mounted) {
      setState(() {
        _themeMode = theme;
        _defaultPlatform = platform;
      });
    }
  }

  ThemeMode get _currentThemeMode {
    switch (_themeMode) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  Future<void> _changeTheme(String mode) async {
    await SettingsRepository.setThemeMode(mode);
    setState(() => _themeMode = mode);
    MrPlayApp.themeModeNotifier.value = _currentThemeMode;
  }

  Future<void> _changeDefaultPlatform(String name) async {
    await SettingsRepository.setDefaultPlatform(name);
    setState(() => _defaultPlatform = name);
  }

  Future<void> _clearCache() async {
    await SettingsRepository.clearCache();
    setState(() {
      _themeMode = 'system';
      _defaultPlatform = 'YouTube';
    });
    MrPlayApp.themeModeNotifier.value = ThemeMode.system;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared')),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader(title: 'Appearance'),
          _SettingsTile(
            icon: Icons.brightness_auto,
            title: 'Theme Mode',
            subtitle: _themeMode.toUpperCase(),
            onTap: () => _showThemePicker(),
          ),
          const _SectionHeader(title: 'Platforms'),
          _SettingsTile(
            icon: Icons.home,
            title: 'Default Platform',
            subtitle: _defaultPlatform,
            onTap: () => _showPlatformPicker(),
          ),
          const _SectionHeader(title: 'Data'),
          _SettingsTile(
            icon: Icons.delete_outline,
            title: 'Clear Cache',
            subtitle: 'Reset all settings to default',
            onTap: _clearCache,
          ),
          const _SectionHeader(title: 'About'),
          _SettingsTile(
            icon: Icons.info_outline,
            title: AppConstants.appName,
            subtitle: 'Version ${AppConstants.appVersion}',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'How we handle your data',
            onTap: () => _openUrl('https://mrplay.app/privacy'),
          ),
          _SettingsTile(
            icon: Icons.star_outline,
            title: 'Rate App',
            subtitle: 'Rate us on the App Store',
            onTap: () => _openUrl(AppConstants.appStoreUrl),
          ),
          _SettingsTile(
            icon: Icons.share,
            title: 'Share App',
            subtitle: 'Tell your friends about MrPlay',
            onTap: () => _shareApp(),
          ),
        ],
      ),
    );
  }

  Future<void> _shareApp() async {
    final uri = Uri.parse(AppConstants.appStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.brightness_5),
              title: const Text('Light'),
              trailing: _themeMode == 'light' ? const Icon(Icons.check, color: Colors.blue) : null,
              onTap: () { _changeTheme('light'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.brightness_3),
              title: const Text('Dark'),
              trailing: _themeMode == 'dark' ? const Icon(Icons.check, color: Colors.blue) : null,
              onTap: () { _changeTheme('dark'); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.brightness_auto),
              title: const Text('System'),
              trailing: _themeMode == 'system' ? const Icon(Icons.check, color: Colors.blue) : null,
              onTap: () { _changeTheme('system'); Navigator.pop(context); },
            ),
          ],
        ),
      ),
    );
  }

  void _showPlatformPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) => ListView.builder(
          controller: scrollController,
          itemCount: PlatformConstants.platforms.length,
          itemBuilder: (context, index) {
            final platform = PlatformConstants.platforms[index];
            return ListTile(
              leading: Icon(Icons.open_in_browser, color: platform.color),
              title: Text(platform.name),
              trailing: _defaultPlatform == platform.name
                  ? const Icon(Icons.check, color: Colors.blue)
                  : null,
              onTap: () {
                _changeDefaultPlatform(platform.name);
                Navigator.pop(context);
              },
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
```

### lib/presentation/widgets/error_widget.dart
```dart
import 'package:flutter/material.dart';

class CustomErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const CustomErrorWidget({
    super.key,
    this.message = 'Something went wrong',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

### lib/presentation/widgets/loading_indicator.dart
```dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Column(
        children: List.generate(3, (index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 120,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )),
      ),
    );
  }
}
```

### lib/presentation/widgets/persistent_webview.dart
```dart
import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:audio_session/audio_session.dart';
import '../../core/constants/youtube_js.dart';
import '../../core/constants/content_blocker_js.dart';
import '../../models/video.dart';
import '../../providers/player_provider.dart';
import '../../services/background_audio_keep_alive.dart';
import 'error_widget.dart';

class PersistentWebView extends ConsumerStatefulWidget {
  const PersistentWebView({super.key});

  @override
  ConsumerState<PersistentWebView> createState() => PersistentWebViewState();
}

class PersistentWebViewState extends ConsumerState<PersistentWebView>
    with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  bool isReady = false;
  bool _isLoading = false;
  String? _pendingUrl;
  String? _loadError;
  Timer? _loadingTimer;
  Timer? _pipOnBackgroundTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadingTimer?.cancel();
    _pipOnBackgroundTimer?.cancel();
    BackgroundAudioKeepAlive.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // App is leaving the foreground (home button, app switcher). iOS pauses
      // video-track media as soon as the app backgrounds, so request PiP before
      // that happens, but only if we keep going to background (control-center /
      // incoming-call transients stay in `inactive`).
      _pipOnBackgroundTimer?.cancel();
      _pipOnBackgroundTimer = Timer(const Duration(milliseconds: 400), () {
        if (mounted &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
          _reassertAudioSession();
          enterPiP(resumePlayback: true);
        }
      });
    } else if (state == AppLifecycleState.paused) {
      _reassertAudioSession();
      enterPiP(resumePlayback: true);
    } else if (state == AppLifecycleState.resumed) {
      _pipOnBackgroundTimer?.cancel();
    }
  }

  Future<void> _reassertAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
    controller.addJavaScriptHandler(
      handlerName: 'playerInfo',
      callback: (args) {
        if (args.isNotEmpty && args.first is Map) {
          _onPlayerInfo(args.first as Map<String, dynamic>);
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'videoState',
      callback: (args) {
        if (args.isNotEmpty && args.first is Map) {
          _onVideoState(args.first as Map<String, dynamic>);
        }
      },
    );
    if (_pendingUrl != null) {
      controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(_pendingUrl!)),
      );
      _pendingUrl = null;
    }
  }

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    if (mounted) setState(() => _isLoading = true);
    if (_loadError != null && mounted) setState(() => _loadError = null);
    _loadingTimer?.cancel();
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _onLoadStop(InAppWebViewController controller, WebUri? url) async {
    _loadingTimer?.cancel();
    if (mounted) setState(() => _isLoading = false);

    final urlStr = url.toString();
    if (urlStr.contains('youtube.com')) {
      if (urlStr.contains('/watch')) {
        Future.delayed(const Duration(milliseconds: 1500), () async {
          await controller.evaluateJavascript(source: '''
            (function() {
              var titleEl = document.querySelector('h1.title, .slim-video-information-title, .ytp-title, #title h1');
              var videoId = window.location.search.match(/[?&]v=([^&]+)/);
              var title = titleEl ? titleEl.textContent.trim().substring(0, 200) : '';
              if (title && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('playerInfo', {
                  id: videoId ? videoId[1] : '',
                  title: title,
                  thumbnailUrl: videoId ? 'https://i.ytimg.com/vi/' + videoId[1] + '/hqdefault.jpg' : '',
                  videoUrl: window.location.href,
                  platform: 'YouTube'
                });
              }
            })();
          ''');
        });
      }
    }
  }

  void _onPlayerInfo(Map<String, dynamic> data) {
    try {
      final title = data['title'] as String? ?? '';
      if (title.isNotEmpty) {
        final video = Video(
          id: data['id'] ?? '',
          title: title,
          thumbnailUrl: data['thumbnailUrl'] ?? '',
          videoUrl: data['videoUrl'] ?? '',
          platform: data['platform'] ?? 'YouTube',
        );
        final currentId = ref.read(playerProvider).currentVideo?.id;
        if (currentId != video.id) {
          ref.read(playerProvider.notifier).play(video);
        }
      }
    } catch (_) {}
  }

  void _onVideoState(Map<String, dynamic> data) {
    try {
      final playing = data['playing'] == true;
      final ended = data['ended'] == true;
      final positionMs = ((data['position'] as num?)?.toDouble() ?? 0) * 1000;
      final durationMs = ((data['duration'] as num?)?.toDouble() ?? 0) * 1000;
      if (ref.read(playerProvider).currentVideo != null) {
        ref.read(playerProvider.notifier).syncState(
              isPlaying: playing,
              position: Duration(milliseconds: positionMs.round()),
              duration: Duration(milliseconds: durationMs.round()),
              ended: ended,
            );
      }
      if (playing && !ended) {
        BackgroundAudioKeepAlive.instance.start();
      } else {
        BackgroundAudioKeepAlive.instance.stop();
      }
    } catch (_) {}
  }

  void controlVideo(String action, {double? position}) {
    final controller = _webViewController;
    if (controller == null) return;
    switch (action) {
      case 'play':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = document.querySelector('video');
            if (v) v.play().catch(function(){});
          })();
        ''');
        break;
      case 'pause':
        controller.evaluateJavascript(source: '''
          (function() {
            var v = document.querySelector('video');
            if (v) v.pause();
          })();
        ''');
        break;
      case 'seek':
        if (position != null) {
          controller.evaluateJavascript(source: '''
            (function() {
              var v = document.querySelector('video');
              if (v) v.currentTime = $position;
            })();
          ''');
        }
        break;
    }
  }

  void loadUrl(String url) {
    _loadingTimer?.cancel();
    _pendingUrl = url;
    if (_webViewController != null) {
      _webViewController!.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
    }
    setState(() {
      isReady = true;
      _isLoading = true;
    });
    _loadingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (request.isForMainFrame != false) {
      if (mounted) {
        setState(() => _loadError = 'Could not load the page: ${error.description}');
      }
    }
  }

  void _onReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse response,
  ) {
    if (request.isForMainFrame != false) {
      if (mounted) {
        setState(() {
          _loadError = 'Server error ${response.statusCode ?? 'unknown'}';
        });
      }
    }
  }

  void _retryLoad() {
    if (!mounted) return;
    setState(() => _loadError = null);
    _webViewController?.reload();
  }

  void enterPiP({bool resumePlayback = false}) {
    _webViewController?.evaluateJavascript(source: '''
      (function() {
        var video = document.querySelector('video');
        if (!video) return;
        if (video.requestPictureInPicture) {
          if (document.pictureInPictureElement) return;
          video.requestPictureInPicture().catch(function(){});
        } else if (video.webkitSetPresentationMode) {
          if (video.webkitPresentationMode !== 'picture-in-picture') {
            video.webkitSetPresentationMode('picture-in-picture');
          }
        }
        if ($resumePlayback) {
          if (video.paused) {
            video.play().catch(function() {
              var btn = document.querySelector('.ytp-play-button');
              if (btn) btn.click();
            });
          }
        }
      })();
    ''');
  }

  void _togglePiP() {
    _webViewController?.evaluateJavascript(source: '''
      (function() {
        var video = document.querySelector('video');
        if (!video) return;
        if (video.requestPictureInPicture) {
          if (document.pictureInPictureElement) {
            document.exitPictureInPicture().catch(function(){});
          } else {
            video.requestPictureInPicture().catch(function(){});
          }
        } else if (video.webkitSetPresentationMode) {
          video.webkitSetPresentationMode(
            video.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture'
          );
        }
      })();
    ''');
  }

  @override
  Widget build(BuildContext context) {
    if (!isReady) return const SizedBox.shrink();

    return Stack(
      children: [
        Positioned.fill(
          child: InAppWebView(
          initialUserScripts: UnmodifiableListView([
            UserScript(
              source: ContentBlockerJS.genericAdBlockerScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            UserScript(
              source: YouTubeJS.visibilityKeepAliveScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            UserScript(
              source: YouTubeJS.searchSpaScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            UserScript(
              source: YouTubeJS.appBannerRemoverScript,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            allowsInlineMediaPlayback: true,
            mediaPlaybackRequiresUserGesture: false,
            allowBackgroundAudioPlaying: true,
            allowsPictureInPictureMediaPlayback: true,
            allowsAirPlayForMediaPlayback: true,
            isFraudulentWebsiteWarningEnabled: false,
            userAgent:
                'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
          ),
          onWebViewCreated: _onWebViewCreated,
          onLoadStart: _onLoadStart,
          onLoadStop: _onLoadStop,
          onReceivedError: _onReceivedError,
          onReceivedHttpError: _onReceivedHttpError,
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url;
            if (url != null) {
              final scheme = url.scheme.toLowerCase();
              if (scheme != 'http' && scheme != 'https' && scheme != 'about' && scheme != 'file') {
                return NavigationActionPolicy.CANCEL;
              }
            }
            return NavigationActionPolicy.ALLOW;
          },
          onCreateWindow: (controller, createWindowAction) async {
            // Open popup/new-window targets (e.g. OAuth "Continue with ...")
            // inside the main WebView instead of dropping them.
            final url = createWindowAction.request.url;
            if (url != null) {
              controller.loadUrl(urlRequest: URLRequest(url: url));
            }
            return false;
          },
          ),
        ),
        if (_loadError != null && !_isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: CustomErrorWidget(
                message: _loadError!,
                onRetry: _retryLoad,
              ),
            ),
          ),
        if (_isLoading)
          Positioned(
            top: 60,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 140,
          right: 16,
          child: GestureDetector(
            onTap: _togglePiP,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.picture_in_picture_alt, color: Colors.white, size: 24),
            ),
          ),
        ),
        Positioned(
          bottom: 80,
          right: 16,
          child: GestureDetector(
            onTap: () {
              _webViewController?.loadUrl(
                urlRequest: URLRequest(url: WebUri('about:blank')),
              );
              _webViewController = null;
              BackgroundAudioKeepAlive.instance.stop();
              ref.read(playerProvider.notifier).dismiss();
              setState(() {
                isReady = false;
                _isLoading = false;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 24),
            ),
          ),
        ),
      ],
    );
  }
}
```

### lib/presentation/widgets/platform_card.dart
```dart
import 'package:flutter/material.dart';
import '../../data/models/platform_model.dart';

class PlatformCard extends StatefulWidget {
  final PlatformModel platform;
  final VoidCallback onTap;

  const PlatformCard({
    super.key,
    required this.platform,
    required this.onTap,
  });

  @override
  State<PlatformCard> createState() => _PlatformCardState();
}

class _PlatformCardState extends State<PlatformCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'youtube': return Icons.play_circle_filled;
      case 'music': return Icons.music_note;
      case 'twitch': return Icons.live_tv;
      case 'rumble': return Icons.video_library;
      case 'duolingo': return Icons.school;
      case 'busuu': return Icons.language;
      case 'babbel': return Icons.translate;
      case 'memrise': return Icons.psychology;
      case 'mondly': return Icons.record_voice_over;
      case 'instagram': return Icons.camera_alt;
      case 'reddit': return Icons.forum;
      case 'facebook': return Icons.facebook;
      case 'x': return Icons.close_fullscreen;
      case 'disney': return Icons.movie;
      case 'hbo': return Icons.tv;
      case 'prime': return Icons.play_circle;
      case 'pinterest': return Icons.push_pin;
      case 'quora': return Icons.help_outline;
      case '9gag': return Icons.emoji_emotions;
      case 'ifunny': return Icons.sentiment_very_satisfied;
      default: return Icons.open_in_browser;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: widget.platform.color ?? Colors.grey,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (widget.platform.color ?? Colors.grey).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _getIconData(widget.platform.icon),
                size: 36,
                color: Colors.white,
              ),
              const SizedBox(height: 8),
              Text(
                widget.platform.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### lib/providers/player_provider.dart
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video.dart';
import '../services/recent_activity_service.dart';
import '../services/spotlight_service.dart';

class PlayerState {
  final Video? currentVideo;
  final bool isPlaying;
  final bool isMinimized;
  final Duration position;
  final Duration duration;

  const PlayerState({
    this.currentVideo,
    this.isPlaying = false,
    this.isMinimized = true,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  PlayerState copyWith({
    Video? currentVideo,
    bool? isPlaying,
    bool? isMinimized,
    Duration? position,
    Duration? duration,
    bool clearVideo = false,
  }) {
    return PlayerState(
      currentVideo: clearVideo ? null : (currentVideo ?? this.currentVideo),
      isPlaying: isPlaying ?? this.isPlaying,
      isMinimized: isMinimized ?? this.isMinimized,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}

class PlayerNotifier extends Notifier<PlayerState> {
  @override
  PlayerState build() => const PlayerState();

  void play(Video video) {
    state = state.copyWith(
      currentVideo: video,
      isPlaying: true,
      isMinimized: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    RecentActivityService.instance.recordVideo(video);
    SpotlightService.index(
      title: video.title,
      subtitle: video.platform.isEmpty ? 'MrPlay' : video.platform,
      url: video.videoUrl,
    );
  }

  void syncState({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool ended = false,
  }) {
    state = state.copyWith(
      isPlaying: ended ? false : (isPlaying ?? state.isPlaying),
      position: position ?? state.position,
      duration: duration ?? state.duration,
    );
  }

  void pause() => state = state.copyWith(isPlaying: false);

  void resume() => state = state.copyWith(isPlaying: true);

  void seekTo(Duration position) => state = state.copyWith(position: position);

  void minimize() => state = state.copyWith(isMinimized: true);

  void expand() => state = state.copyWith(isMinimized: false);

  void dismiss() => state = const PlayerState();
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
```

### lib/services/background_audio_keep_alive.dart
```dart
import 'package:audioplayers/audioplayers.dart';

class BackgroundAudioKeepAlive {
  BackgroundAudioKeepAlive._();

  static final BackgroundAudioKeepAlive instance = BackgroundAudioKeepAlive._();

  final AudioPlayer _player = AudioPlayer();
  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0);
      await _player.play(AssetSource('audio/silence.wav'));
    } catch (_) {
      _running = false;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _player.stop();
    } catch (_) {}
  }
}
```

### lib/services/recent_activity_service.dart
```dart
import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video.dart';

class RecentActivityService {
  RecentActivityService._();

  static final RecentActivityService instance = RecentActivityService._();

  static const String _prefsKey = 'recent_videos';
  static const String _appGroupId = 'group.com.mrplay.shared';
  static const String _widgetKind = 'MrPlayRecentWidget';
  static const String _widgetDataKey = 'recent';
  static const int _maxEntries = 5;

  bool _groupConfigured = false;

  Future<void> _configureWidget() async {
    if (_groupConfigured) return;
    await HomeWidget.setAppGroupId(_appGroupId);
    _groupConfigured = true;
  }

  Future<List<Map<String, String>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((dynamic item) {
        final map = item as Map<String, dynamic>;
        return <String, String>{
          'title': (map['title'] as String?) ?? '',
          'url': (map['url'] as String?) ?? '',
          'platform': (map['platform'] as String?) ?? '',
        };
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> recordVideo(Video video) async {
    final entry = <String, String>{
      'title': video.title,
      'url': video.videoUrl,
      'platform': video.platform.isEmpty ? 'Web' : video.platform,
    };
    final entries = await load();
    entries.removeWhere((e) => e['url'] == video.videoUrl);
    entries.insert(0, entry);
    if (entries.length > _maxEntries) {
      entries.removeRange(_maxEntries, entries.length);
    }
    await _persist(entries);
  }

  Future<void> clear() async {
    await _persist(const []);
  }

  Future<void> _persist(List<Map<String, String>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(entries));
    try {
      await _configureWidget();
      await HomeWidget.saveWidgetData(_widgetDataKey, jsonEncode(entries));
      await HomeWidget.updateWidget(iOSName: _widgetKind);
    } catch (_) {}
  }
}
```

### lib/services/spotlight_service.dart
```dart
import 'package:flutter/services.dart';

class SpotlightService {
  SpotlightService._();

  static const MethodChannel _channel = MethodChannel('com.mrplay/spotlight');

  static void Function(String url)? _openHandler;

  static void setOpenHandler(void Function(String url) handler) {
    _openHandler = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') {
        final url = call.arguments as String?;
        if (url != null && url.isNotEmpty) _openHandler?.call(url);
      }
    });
  }

  static Future<void> index({
    required String title,
    required String subtitle,
    required String url,
  }) async {
    try {
      await _channel.invokeMethod('index', {
        'title': title,
        'subtitle': subtitle,
        'url': url,
      });
    } catch (_) {}
  }

  static Future<void> remove(String url) async {
    try {
      await _channel.invokeMethod('remove', {'url': url});
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await _channel.invokeMethod('clear');
    } catch (_) {}
  }
}
```

### lib/services/share_link_handler.dart
```dart
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareLinkHandler {
  ShareLinkHandler._();

  static final ShareLinkHandler instance = ShareLinkHandler._();

  void init(void Function(String url) onOpen) {
    ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) => _handle(files, onOpen),
    );
    ReceiveSharingIntent.instance.getInitialMedia().then(
      (files) => _handle(files, onOpen),
    );
  }

  void _handle(List<SharedMediaFile> files, void Function(String url) onOpen) {
    for (final file in files) {
      final isLink =
          file.type == SharedMediaType.url || file.type == SharedMediaType.text;
      if (isLink && file.path.isNotEmpty) {
        onOpen(file.path);
      }
    }
  }
}
```

### lib/widgets/full_player.dart
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../models/video.dart';
import '../data/models/favorite_video.dart';
import '../data/repositories/favorites_repository.dart';
import '../app.dart';

class FullPlayerWidget extends ConsumerStatefulWidget {
  const FullPlayerWidget({super.key});

  @override
  ConsumerState<FullPlayerWidget> createState() => _FullPlayerWidgetState();
}

class _FullPlayerWidgetState extends ConsumerState<FullPlayerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(0, 1),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));
    _slideController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        ref.read(playerProvider.notifier).minimize();
        _slideController.reset();
      }
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final shouldMinimize =
        (details.primaryVelocity != null && details.primaryVelocity! > 500) ||
            _dragOffset > 150;
    if (shouldMinimize) {
      MrPlayApp.webViewKey.currentState?.enterPiP();
      _slideController.forward();
    } else {
      _slideController.reverse();
    }
    setState(() => _dragOffset = 0);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      if (_dragOffset < 0) _dragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    final video = state.currentVideo;
    if (video == null || state.isMinimized) return const SizedBox.shrink();

    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final progress = (_dragOffset / screenHeight).clamp(0.0, 1.0);
    final translateY = _dragOffset * (1 - progress * 0.3);
    final scale = 1 - progress * 0.05;
    final opacity = 1 - progress;

    return SlideTransition(
      position: _slideAnimation,
      child: GestureDetector(
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Container(
          color: Colors.black.withValues(alpha: 0.95 * opacity),
          child: Stack(
            children: [
              Transform.translate(
                offset: Offset(0, translateY),
                child: Transform.scale(
                  scale: scale,
                  child: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(top: topPadding + 20),
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 3,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.grey[600],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: video.thumbnailUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: video.thumbnailUrl,
                                      fit: BoxFit.contain,
                                      placeholder: (_, __) => Container(
                                        color: Colors.black,
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                                          ),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey[900],
                                      child: const Center(
                                        child: Icon(Icons.play_circle, color: Colors.white38, size: 64),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  video.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  video.platform.isNotEmpty ? video.platform : 'YouTube',
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: Colors.red,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.red,
                              overlayColor: Colors.red.withValues(alpha: 0.2),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: state.duration.inMilliseconds > 0
                                  ? state.position.inMilliseconds /
                                      state.duration.inMilliseconds
                                  : 0,
                              onChanged: (value) {
                                final pos = Duration(
                                  milliseconds: (value * state.duration.inMilliseconds).round(),
                                );
                                ref.read(playerProvider.notifier).seekTo(pos);
                                MrPlayApp.webViewKey.currentState
                                    ?.controlVideo('seek', position: pos.inMilliseconds / 1000.0);
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(state.position),
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                                Text(
                                  _formatDuration(state.duration),
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                iconSize: 48,
                                icon: Icon(
                                  state.isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  final notifier = ref.read(playerProvider.notifier);
                                  final webView = MrPlayApp.webViewKey.currentState;
                                  if (state.isPlaying) {
                                    notifier.pause();
                                    webView?.controlVideo('pause');
                                  } else {
                                    notifier.resume();
                                    webView?.controlVideo('play');
                                  }
                                },
                              ),
                            ],
                          ),
                          const Spacer(),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: topPadding + 4,
                right: 16,
                child: Row(
                  children: [
                    _FavoriteButton(
                      key: ValueKey(video.id),
                      video: video,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => ref.read(playerProvider.notifier).dismiss(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$minutes:$seconds';
  }
}

class _FavoriteButton extends StatefulWidget {
  final Video video;

  const _FavoriteButton({super.key, required this.video});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool? _isFavorite;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isFavorite = await FavoritesRepository.isFavorite(widget.video.id);
    if (mounted) setState(() => _isFavorite = isFavorite);
  }

  Future<void> _toggle() async {
    final video = widget.video;
    if (_isFavorite == true) {
      await FavoritesRepository.remove(video.id);
    } else {
      await FavoritesRepository.add(
        FavoriteVideo(
          id: video.id,
          title: video.title,
          channel: video.platform.isEmpty ? 'YouTube' : video.platform,
          thumbnailUrl: video.thumbnailUrl,
          platformUrl: video.videoUrl,
          addedAt: DateTime.now(),
        ),
      );
    }
    if (mounted) setState(() => _isFavorite = _isFavorite != true);
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = _isFavorite == true;
    return IconButton(
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: isFavorite ? Colors.red : Colors.white54,
      ),
      onPressed: _isFavorite == null ? null : _toggle,
    );
  }
}
```

### lib/widgets/mini_player.dart
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../app.dart';

class MiniPlayerWidget extends ConsumerStatefulWidget {
  const MiniPlayerWidget({super.key});

  @override
  ConsumerState<MiniPlayerWidget> createState() => _MiniPlayerWidgetState();
}

class _MiniPlayerWidgetState extends ConsumerState<MiniPlayerWidget> {
  double _dragOffset = 0;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      if (_dragOffset < 0) _dragOffset = 0;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final shouldEnterPiP =
        (details.primaryVelocity != null && details.primaryVelocity! > 400) ||
            _dragOffset > 150;
    if (shouldEnterPiP) {
      MrPlayApp.webViewKey.currentState?.enterPiP();
    }
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    final video = state.currentVideo;
    if (video == null || !state.isMinimized) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => ref.read(playerProvider.notifier).expand(),
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Container(
        height: 64,
        color: const Color(0xFF1C1C1E),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: state.duration.inMilliseconds > 0
                  ? state.position.inMilliseconds / state.duration.inMilliseconds
                  : 0,
              backgroundColor: Colors.white10,
              color: Colors.red,
              minHeight: 2,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: video.thumbnailUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: video.thumbnailUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: Colors.grey[800]),
                              )
                            : Container(
                                color: Colors.grey[800],
                                child: const Icon(Icons.music_note, color: Colors.white38),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            video.platform.isNotEmpty ? video.platform : 'YouTube',
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        final notifier = ref.read(playerProvider.notifier);
                        final webView = MrPlayApp.webViewKey.currentState;
                        if (state.isPlaying) {
                          notifier.pause();
                          webView?.controlVideo('pause');
                        } else {
                          notifier.resume();
                          webView?.controlVideo('play');
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                      onPressed: () => ref.read(playerProvider.notifier).dismiss(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### lib/widgets/persistent_player_shell.dart
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import 'mini_player.dart';
import 'full_player.dart';

class PersistentPlayerShell extends ConsumerWidget {
  const PersistentPlayerShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final hasVideo = state.currentVideo != null;

    if (!hasVideo) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: state.isMinimized
            ? const MiniPlayerWidget(key: ValueKey('mini'))
            : const FullPlayerWidget(key: ValueKey('full')),
      ),
    );
  }
}
```

### lib/widgets/unified_banner_ad_slot.dart
```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ad_config.dart';
import '../core/theme/app_colors.dart';

class UnifiedBannerAdSlot extends StatefulWidget {
  final Color backgroundColor;
  final bool isVisible;

  const UnifiedBannerAdSlot({
    super.key,
    this.backgroundColor = AppColors.surface,
    this.isVisible = true,
  });

  @override
  State<UnifiedBannerAdSlot> createState() => _UnifiedBannerAdSlotState();
}

class _UnifiedBannerAdSlotState extends State<UnifiedBannerAdSlot>
    with WidgetsBindingObserver {
  BannerAd? _bannerAd;
  Widget? _adWidget;
  AdSize? _adSize;
  bool _adLoaded = false;
  bool _isDismissed = false;
  bool _isAppBackgrounded = false;
  Timer? _reappearTimer;
  bool _adsInitiated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_adsInitiated) {
      _adsInitiated = true;
      _loadBannerAd();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state == AppLifecycleState.paused;
    if (bg != _isAppBackgrounded) {
      setState(() => _isAppBackgrounded = bg);
    }
  }

  Future<void> _loadBannerAd() async {
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      MediaQuery.of(context).size.width.round(),
    );
    if (!mounted) return;
    _adSize = size;
    _bannerAd = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: size ?? AdSize.largeBanner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          _adWidget = AdWidget(key: ValueKey(ad.hashCode), ad: ad as BannerAd);
          setState(() => _adLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() => _bannerAd = null);
        },
      ),
    )..load();
  }

  void _handleDismiss() {
    setState(() => _isDismissed = true);
    _reappearTimer?.cancel();
    _reappearTimer = Timer(
      const Duration(minutes: 5),
      () {
        if (!mounted) return;
        setState(() => _isDismissed = false);
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reappearTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_adLoaded || _bannerAd == null || _isDismissed || !widget.isVisible || _isAppBackgrounded) {
      return const SizedBox.shrink();
    }

    final size = _adSize;
    final bannerWidth = size == null ? 320.0 : size.width.toDouble();
    final bannerHeight = size == null ? 100.0 : size.height.toDouble();

    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: SizedBox(
        width: bannerWidth,
        height: bannerHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              border: Border.all(color: Colors.white.withAlpha(15), width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(child: _adWidget!),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: _handleDismiss,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: AppColors.border,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 13,
                        color: Colors.white60,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

### test/widget_test.dart
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrplay/app.dart';

void main() {
  testWidgets('App renders hub page', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MrPlayApp()));
    expect(find.text('MrPlay'), findsOneWidget);
  });
}
```

## 8. Documentation

### NATIVE_FEATURES.md
```markdown
# Native iOS Features — Setup Guide

This document explains the manual Xcode steps needed to finish the native iOS features.
The Dart side is already fully wired; the remaining work happens in Xcode because adding
app-extension targets cannot be scripted from a Windows machine.

## What is already done (code)

| Feature | Dart | iOS native |
|---|---|---|
| Home Screen Widget | `lib/services/recent_activity_service.dart` saves the last 5 watched videos and triggers a widget refresh on every `play()` | Widget extension source + Info.plist ready in `ios/HomeWidgetExtension/` |
| Widget tap → open video | `lib/app.dart` listens to `HomeWidget.widgetClicked` / `initiallyLaunchedFromHomeWidget` | `mrplay://` URL scheme registered in `ios/Runner/Info.plist` |
| Spotlight search | `lib/services/spotlight_service.dart` indexes videos on every `play()` | `CoreSpotlight` channel in `ios/Runner/AppDelegate.swift`, handles open activity |
| Share Extension | `lib/services/share_link_handler.dart` routes shared text/URLs into the WebView | `AppGroupId` + `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` scheme in `ios/Runner/Info.plist` |

One shared App Group is used everywhere: **`group.com.mrplay.shared`**.

---

## Prerequisites

- A Mac with Xcode (the app must be signed with a developer team).
- A **paid** Apple Developer account. App Groups / App Extensions are not available with a
  free personal team.
- `flutter pub get` already run (plugins `home_widget` and `receive_sharing_intent` are resolved).

---

## Part 1 — Home Screen Widget

### 1. Create the App Group

In Xcode: open the project, select the **Runner** target →
**Signing & Capabilities** → **+ Capability** → **App Groups**.
Click **+** and add the container **`group.com.mrplay.shared`**.
Xcode will create `Runner/Runner.entitlements` with the group.

### 2. Create the Widget Extension target

1. **File → New → Target…** → **Widget Extension** → Next.
2. Product name: **`HomeWidgetExtension`**
   (the folder `ios/HomeWidgetExtension/` already exists with the code below).
3. Bundle ID: `com.mrplay.app.HomeWidgetExtension` (Xcode proposes it; keep it).
4. Keep "Include Live Activity" unchecked.
5. In the target's **Signing & Capabilities**: add the **App Groups** capability and
   check **`group.com.mrplay.shared`**.
6. Set the extension's **Deployment Target** to **iOS 14.0** or higher
   (WidgetKit requires iOS 14+; the main app stays on 13.0).

### 3. Replace the generated files

Xcode generates a template `HomeWidgetExtension.swift` and `Info.plist` in
`ios/HomeWidgetExtension/`. Replace them with the two files already in this repo:

- `ios/HomeWidgetExtension/HomeWidgetExtension.swift`
- `ios/HomeWidgetExtension/Info.plist`

If Xcode's "Create folder references" wizard made a different folder, copy the two files
from `ios/HomeWidgetExtension/` into the target's folder and remove the template file.

### 4. Build & verify

- Run the app once (the widget refreshes whenever a video starts playing).
- Add the widget from the widget gallery: it shows the last 3 watched videos.
- Tapping a row (medium size) or the widget (small size) opens that video in MrPlay.
- Tapping a row deep-links via `mrplay://open?url=…&homeWidget` and `home_widget`
  routes it back to the Dart `_openFromWidget` handler in `lib/app.dart`.

---

## Part 2 — Spotlight Search

**No Xcode work required.** When a video is played, `play()` calls
`SpotlightService.index(...)`, which invokes the `com.mrplay/spotlight` channel
implemented in `ios/Runner/AppDelegate.swift`.

- Search for a video name on the device → it appears in Spotlight.
- Tapping a result opens the app and loads the video via
  `application(_:continue:restorationHandler:)` → Dart `_openFromWidget`.
- Indexed items expire after 30 days automatically.

---

## Part 3 — Share Extension

The Dart handler (`lib/services/share_link_handler.dart`) is already active. You must add
the native Share Extension target so the app can actually receive shares.

### 1. Create the Share Extension target

1. **File → New → Target…** → **Share Extension** → Next.
2. Product name: **`ShareExtension`**, bundle ID `com.mrplay.app.ShareExtension`.
3. Make the share extension's **Deployment Target match the Runner** (13.0).

### 2. Update the share extension Info.plist

Open the generated `ios/ShareExtension/Info.plist` and add:

```xml
<key>AppGroupId</key>
<string>group.com.mrplay.shared</string>
```

and make sure the activation rule supports text and web URLs:

```xml
<key>NSExtensionActivationSupportsText</key>
<true/>
<key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
<integer>1</integer>
```

### 3. Point the share controller at the plugin

Replace the generated `ios/ShareExtension/ShareViewController.swift` with:

```swift
import receive_sharing_intent

class ShareViewController: RSIShareViewController {}
```

### 4. Update the Podfile

Open `ios/Podfile` and add the extension target under `Runner`:

```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  target 'ShareExtension' do
    inherit! :search_paths
  end
end
```

Then run `pod install` on the Mac.

### 5. App Group on the extension

In the **ShareExtension** target → **Signing & Capabilities** → **App Groups** →
check **`group.com.mrplay.shared`**.

### 6. Build phase order

In the **Runner** target → **Build Phases**, drag **Embed Foundation Extension**
above **Thin Binary** (prevents "No such module 'receive_sharing_intent'").

### 7. Verify

Share a link from Safari via the share sheet → "ShareExtension" → MrPlay opens with the
page loaded in the WebView.

---

## Part 4 — Siri Shortcuts (future enhancement)

Not implemented yet. To add it, create an **App Intents** extension in Xcode and expose
intents such as "Play last watched video". The deep-link plumbing already exists
(`mrplay://open?url=…`), so the intent only needs to emit that URL.

---

## Verification checklist

- [ ] App Group `group.com.mrplay.shared` enabled on **Runner**, **HomeWidgetExtension**, and **ShareExtension**.
- [ ] `HomeWidgetExtension` deployment target ≥ iOS 14.0.
- [ ] `ios/HomeWidgetExtension/HomeWidgetExtension.swift` + `Info.plist` are the repo versions.
- [ ] Share extension `ShareViewController` inherits `RSIShareViewController`.
- [ ] `pod install` ran after editing the Podfile.
- [ ] Build in Xcode; `flutter analyze` reports no issues.

## App Store notes

- The widget and share extension are standard, permitted app extensions.
- No private APIs are used; `CoreSpotlight` and `WidgetKit` are public frameworks.
- If you also submit screenshots of the widget, the widget gallery screenshot must match
  the real widget exactly (required by App Review).
```
