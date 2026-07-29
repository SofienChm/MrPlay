# App Review Notes

## Summary for Reviewers
MrPlay is a multi-platform video/content hub app. It uses WKWebView to load the official mobile websites of video and content platforms (youtube.com, twitch.tv, instagram.com, etc.). No content is downloaded, cached, or modified. All video playback occurs through the platforms' own web players.

The app provides native iOS features including:
- A multi-platform hub grid (20+ platforms)
- Persistent mini player that keeps videos playing while browsing
- Background audio playback (AVAudioSession configured for .playback)
- Lock screen and notification center controls (MPNowPlayingInfoCenter)
- Dark/Light theme support
- Platform search and favorites

## What the App Does NOT Do
- Does NOT download or cache videos
- Does NOT modify content from any platform
- Does NOT use network-level ad blocking
- Does NOT provide any content that isn't available through the platforms' own mobile websites

## Background Audio
Background audio is supported via AVAudioSession configured with .playback category. This allows users to continue listening to audio (music, podcasts, educational content) when the app goes to the background or the screen locks. Audio playback is controlled via the native iOS notification center and lock screen controls.

## Demo Account
Please refer to demo_account.md for test credentials.
