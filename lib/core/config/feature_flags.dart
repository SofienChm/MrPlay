/// Compile-time switches for behaviour that still needs device validation.
abstract final class FeatureFlags {
  /// When false, WebKit owns Now Playing and the lock-screen controls of the
  /// page media (trusted Media Session commands); the app never writes
  /// MPNowPlayingInfoCenter. Must match `useNativeRemoteCommands` in
  /// AppDelegate.swift.
  static const bool nativeLockScreen = false;

  /// A backgrounded session older than this goes back to the hub on resume
  /// (never while something is playing).
  static const Duration sessionTimeout = Duration(hours: 25);
}
