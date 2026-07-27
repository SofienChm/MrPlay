import UIKit
import Flutter
import AVFoundation
import MediaPlayer
import WebKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
      try audioSession.setActive(true)
    } catch {
      print("MrPlay: Failed to set audio session: \(error)")
    }
    
    let controller = window?.rootViewController as! FlutterViewController
    let audioChannel = FlutterMethodChannel(
      name: "com.mrplay/audio",
      binaryMessenger: controller.binaryMessenger
    )
    
    audioChannel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "enableBackgroundAudio":
        self?.enableBackgroundAudio()
        result(nil)
      case "disableBackgroundAudio":
        self?.disableBackgroundAudio()
        result(nil)
      case "updateNowPlayingInfo":
        if let args = call.arguments as? [String: Any] {
          self?.updateNowPlayingInfo(args)
        }
        result(nil)
      case "setPlaybackState":
        if let isPlaying = call.arguments as? Bool {
          self?.setPlaybackState(isPlaying: isPlaying)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let webviewChannel = FlutterMethodChannel(
      name: "com.mrplay/webview",
      binaryMessenger: controller.binaryMessenger
    )
    
    webviewChannel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "configureForPlayback":
        self?.configureWKWebViewForPlayback()
        result(nil)
      case "configureForBackground":
        self?.configureWKWebViewForBackground()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    self.setupRemoteControls()
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  func findWKWebView(in view: UIView) -> WKWebView? {
    if let webView = view as? WKWebView {
      return webView
    }
    for subview in view.subviews {
      if let found = findWKWebView(in: subview) {
        return found
      }
    }
    return nil
  }
  
  func configureWKWebViewForPlayback() {
    guard let webView = findWKWebView(in: self.window ?? UIView()) else {
      print("MrPlay: WKWebView not found, retrying in 0.5s")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.configureWKWebViewForPlayback()
      }
      return
    }
    
    let config = webView.configuration
    config.allowsInlineMediaPlayback = true
    if #available(iOS 15.0, *) {
      config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypes(rawValue: 0)
    } else {
      config.mediaTypesRequiringUserActionForPlayback = []
    }
    config.allowsAirPlayForMediaPlayback = true
    
    webView.allowsBackForwardNavigationGestures = true
    
    print("MrPlay: WKWebView configured for inline + background playback")
  }
  
  func configureWKWebViewForBackground() {
    guard let webView = findWKWebView(in: self.window ?? UIView()) else {
      return
    }
    webView.configuration.allowsInlineMediaPlayback = true
    if #available(iOS 15.0, *) {
      webView.configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypes(rawValue: 0)
    } else {
      webView.configuration.mediaTypesRequiringUserActionForPlayback = []
    }
  }
  
  func enableBackgroundAudio() {
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("MrPlay: Failed to enable background audio: \(error)")
    }
  }
  
  func disableBackgroundAudio() {
    do {
      try AVAudioSession.sharedInstance().setActive(false)
    } catch {
      print("MrPlay: Failed to disable background audio: \(error)")
    }
  }
  
  func updateNowPlayingInfo(_ info: [String: Any]) {
    var nowPlayingInfo = [String: Any]()
    
    if let title = info["title"] as? String, !title.isEmpty {
      nowPlayingInfo[MPMediaItemPropertyTitle] = title
    } else {
      nowPlayingInfo[MPMediaItemPropertyTitle] = "MrPlay"
    }
    
    if let artist = info["artist"] as? String, !artist.isEmpty {
      nowPlayingInfo[MPMediaItemPropertyArtist] = artist
    } else {
      nowPlayingInfo[MPMediaItemPropertyArtist] = "YouTube"
    }
    
    if let duration = info["duration"] as? Double, duration > 0 {
      nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    }
    
    if let currentTime = info["currentTime"] as? Double, currentTime > 0 {
      nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    }
    
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
    
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }
  
  func setPlaybackState(isPlaying: Bool) {
    let state: MPNowPlayingPlaybackState = isPlaying ? .playing : .paused
    MPNowPlayingInfoCenter.default().playbackState = state
  }
  
  func setupRemoteControls() {
    let commandCenter = MPRemoteCommandCenter.shared()
    
    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.sendCommandToFlutter("play")
      return .success
    }
    
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.sendCommandToFlutter("pause")
      return .success
    }
    
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.sendCommandToFlutter("toggle")
      return .success
    }
    
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
  }
  
  func sendCommandToFlutter(_ command: String) {
    DispatchQueue.main.async {
      let controller = self.window?.rootViewController as? FlutterViewController
      let channel = FlutterMethodChannel(
        name: "com.mrplay/audio",
        binaryMessenger: controller!.binaryMessenger
      )
      channel.invokeMethod("remoteControlEvent", arguments: command)
    }
  }
  
  override func applicationDidEnterBackground(_ application: UIApplication) {
    backgroundTask = application.beginBackgroundTask(withName: "MrPlayAudio") {
      application.endBackgroundTask(self.backgroundTask)
      self.backgroundTask = .invalid
    }
    
    do {
      try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      print("MrPlay: Failed to keep audio active: \(error)")
    }
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
      if self.backgroundTask != .invalid {
        application.endBackgroundTask(self.backgroundTask)
        self.backgroundTask = .invalid
      }
    }
  }
  
  override func applicationWillEnterForeground(_ application: UIApplication) {
    if backgroundTask != .invalid {
      application.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
    
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("MrPlay: Failed to reactivate audio: \(error)")
    }
  }
}
