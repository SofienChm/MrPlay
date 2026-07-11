import Flutter
import UIKit
import AVFoundation
import MediaPlayer
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var keepWebViewAlive = false
  private var isPaused = false
  private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
  private var methodChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.mrplay/background_playback",
      binaryMessenger: controller.binaryMessenger
    )
    methodChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "startForegroundService":
        let args = call.arguments as? [String: Any]
        let title = args?["title"] as? String ?? "MrPlay Audio"
        self.isPaused = false
        self.startBackgroundAudio(title: title)
        result(nil)
      case "stopForegroundService":
        self.stopBackgroundAudio()
        result(nil)
      case "updateNowPlaying":
        let args = call.arguments as? [String: Any]
        let title = args?["title"] as? String ?? "MrPlay Audio"
        self.updateNowPlayingInfo(title: title, rate: self.isPaused ? 0.0 : 1.0)
        result(nil)
      case "wasPaused":
        result(self.isPaused)
      case "clearPaused":
        self.isPaused = false
        result(nil)
      case "enterPip":
        result(FlutterMethodNotImplemented)
      case "moveTaskToBack":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    setupRemoteCommands()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupRemoteCommands() {
    let cmdCenter = MPRemoteCommandCenter.shared()
    cmdCenter.playCommand.addTarget { [weak self] _ in
      self?.resumePlayback()
      return .success
    }
    cmdCenter.pauseCommand.addTarget { [weak self] _ in
      self?.pausePlayback()
      return .success
    }
    cmdCenter.stopCommand.addTarget { [weak self] _ in
      self?.pausePlayback()
      self?.stopBackgroundAudio()
      return .success
    }
  }

  private func pausePlayback() {
    isPaused = true
    updateNowPlayingInfo(title: nil, rate: 0.0)
    // Send method channel to Dart FIRST (before audio deactivation)
    // to give Dart time to set __mrplayUserPaused before the interval fires
    methodChannel?.invokeMethod("pauseFromNative", arguments: nil)
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      print("Failed to deactivate audio session: \(error)")
    }
    let js = """
      window.__mrplayUserPaused = true;
      if (window.__mrplaySpoofInterval) { clearInterval(window.__mrplaySpoofInterval); window.__mrplaySpoofInterval = null; }
      if (window.__mrplayKeepAliveInterval) { clearInterval(window.__mrplayKeepAliveInterval); window.__mrplayKeepAliveInterval = null; }
      if (window.__mrplayBgInterval) { clearInterval(window.__mrplayBgInterval); window.__mrplayBgInterval = null; }
      var v = document.querySelector('video');
      if (v && !v.paused) v.pause();
    """
    evaluateInAllWebViews(js)
  }

  private func resumePlayback() {
    isPaused = false
    updateNowPlayingInfo(title: nil, rate: 1.0)
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true)
    } catch {
      print("Failed to reactivate audio session: \(error)")
    }
    let js = """
      window.__mrplayUserPaused = false;
      var v = document.querySelector('video');
      if (v && v.paused) v.play().catch(function(){});
    """
    evaluateInAllWebViews(js)
    methodChannel?.invokeMethod("resumeFromNative", arguments: nil)
    startBackgroundTask()
  }

  private func evaluateInAllWebViews(_ js: String) {
    var allWebViews: [WKWebView] = []
    for scene in UIApplication.shared.connectedScenes {
      if let windowScene = scene as? UIWindowScene {
        for window in windowScene.windows {
          collectWKWebViews(in: window, into: &allWebViews)
        }
      }
    }
    if allWebViews.isEmpty {
      for window in UIApplication.shared.windows {
        collectWKWebViews(in: window, into: &allWebViews)
      }
    }
    if allWebViews.isEmpty, let root = window?.rootViewController?.view {
      collectWKWebViews(in: root, into: &allWebViews)
    }
    for wv in allWebViews {
      wv.evaluateJavaScript(js, completionHandler: nil)
    }
  }

  private func collectWKWebViews(in view: UIView, into result: inout [WKWebView]) {
    if let wv = view as? WKWebView { result.append(wv) }
    for sub in view.subviews { collectWKWebViews(in: sub, into: &result) }
  }

  private func updateNowPlayingInfo(title: String?, rate: Float) {
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    if let t = title { info[MPMediaItemPropertyTitle] = t }
    info[MPNowPlayingInfoPropertyPlaybackRate] = rate
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func startBackgroundAudio(title: String) {
    keepWebViewAlive = true
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true)
    } catch {
      print("Failed to configure audio session: \(error)")
    }
    UIApplication.shared.isIdleTimerDisabled = true
    updateNowPlayingInfo(title: title, rate: 1.0)
    startBackgroundTask()
  }

  private func stopBackgroundAudio() {
    keepWebViewAlive = false
    isPaused = false
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      print("Failed to deactivate audio session: \(error)")
    }
    UIApplication.shared.isIdleTimerDisabled = false
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    endBackgroundTask()
  }

  private func startBackgroundTask() {
    endBackgroundTask()
    backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "webview-audio") {
      [weak self] in
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    guard backgroundTaskId != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTaskId)
    backgroundTaskId = .invalid
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    if keepWebViewAlive && !isPaused {
      startBackgroundTask()
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    endBackgroundTask()
  }
}
