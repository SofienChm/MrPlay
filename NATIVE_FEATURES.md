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
