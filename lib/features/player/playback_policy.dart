/// Pure playback decisions, kept out of the engine so they are unit-tested.
abstract final class PlaybackPolicy {
  static const Duration unmuteThrottle = Duration(milliseconds: 500);
  static const Duration pipStuckGrace = Duration(milliseconds: 800);
  static const Duration inlineForceThrottle = Duration(seconds: 3);

  /// Transient "interruptions" right after our own play start are the ad SDK
  /// / WebKit settling the shared audio session, not a real interruption.
  static const Duration interruptionGrace = Duration(milliseconds: 2500);

  /// A video restarting on its own this soon after a background user pause is
  /// undone instead of overriding the pause.
  static const Duration userPauseGuard = Duration(seconds: 15);

  /// Clamps a seek target into `[0, duration]` (unknown duration: no cap).
  static Duration clampSeek(Duration target, Duration duration) {
    var t = target.isNegative ? Duration.zero : target;
    if (duration > Duration.zero && t > duration) t = duration;
    return t;
  }

  /// Unmute only a playing, muted video with no ad showing, throttled so
  /// YouTube's async re-mute gets retried without hammering the page.
  static bool shouldUnmute({
    required bool playing,
    required bool ended,
    required bool muted,
    required bool adShowing,
    required Duration sinceLastAttempt,
  }) =>
      playing && !ended && muted && !adShowing && sinceLastAttempt >= unmuteThrottle;

  /// A regular video that stopped on its own in the background (not ended,
  /// not paused by the user, the system or a queue handoff) needs the webview
  /// kept reachable for a lock-screen play. Music has its own keep-alive.
  static bool shouldHoldWebView({
    required bool wasPlaying,
    required bool playing,
    required bool ended,
    required bool backgrounded,
    required bool backgroundAudio,
    required bool isMusic,
    required bool userPaused,
    required bool systemPaused,
    required bool handoffPending,
  }) {
    if (!wasPlaying || playing || ended) return false;
    if (!backgrounded || !backgroundAudio || isMusic) return false;
    return !userPaused && !systemPaused && !handoffPending;
  }

  /// Un-stick a video left in PiP mode with no PiP window (renders black),
  /// only in the foreground, after a grace period, throttled.
  static bool shouldForceInline({
    required bool pipStuck,
    required bool backgrounded,
    required Duration stuckFor,
    required Duration sinceLastForce,
  }) =>
      pipStuck && !backgrounded && stuckFor >= pipStuckGrace && sinceLastForce >= inlineForceThrottle;

  /// The ad blocker ends an unskippable ad by jumping to its end, which fires
  /// `ended` while the ad is still flagged: that must not advance the queue.
  static bool isRealEnd({required bool ended, required bool adShowing}) => ended && !adShowing;
}
