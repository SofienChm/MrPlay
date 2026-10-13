# Files/dirs Claude should NOT read, search, or list (saves tokens)

## Build / generated
build/
.dart_tool/
.flutter-plugins-dependencies
.metadata
ios/Pods/
ios/build/
ios/.symlinks/
ios/Flutter/ephemeral/
ios/Flutter/Generated.xcconfig
**/*.g.dart
**/*.freezed.dart
**/GeneratedPluginRegistrant.*

## Logs
*.log
flutter_serve.log
flutter_serve_err.log

## Lockfiles
pubspec.lock
ios/Podfile.lock

## Binary / media assets
assets/audio/
assets/images/
assets/icons/
web/*.jpg
web/*.png
**/*.png
**/*.jpg
**/*.jpeg
**/*.mp3
**/*.mp4
**/*.ttf

## IDE / VCS
.idea/
*.iml
.git/

## Large docs (grep for keywords instead of reading)
PROJECT_MAP.md
APP_STORE_ASSETS.md
