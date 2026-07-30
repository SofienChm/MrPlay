import UIKit
import Flutter
import AVFoundation
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate {
  var audioSession: AVAudioSession?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Setup audio session for background playback
    setupAudioSession()

    // Setup method channel for Flutter communication
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
      case "togglePiP":
        self?.togglePiP()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Setup remote control events (notification center controls)
    setupRemoteControls()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func setupAudioSession() {
    audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession?.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers, .duckOthers])
      try audioSession?.setActive(true)
    } catch {
      print("Failed to set audio session: \(error)")
    }
  }

  func enableBackgroundAudio() {
    do {
      try audioSession?.setActive(true)
    } catch {
      print("Failed to activate audio session: \(error)")
    }
  }

  func disableBackgroundAudio() {
    do {
      try audioSession?.setActive(false)
    } catch {
      print("Failed to deactivate audio session: \(error)")
    }
  }

  func updateNowPlayingInfo(_ info: [String: Any]) {
    var nowPlayingInfo = [String: Any]()

    if let title = info["title"] as? String {
      nowPlayingInfo[MPMediaItemPropertyTitle] = title
    }
    if let artist = info["artist"] as? String {
      nowPlayingInfo[MPMediaItemPropertyArtist] = artist
    }
    if let duration = info["duration"] as? Double {
      nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let currentTime = info["currentTime"] as? Double {
      nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  func setPlaybackState(isPlaying: Bool) {
    let state: MPNowPlayingPlaybackState = isPlaying ? .playing : .paused
    MPNowPlayingInfoCenter.default().playbackState = state
  }

  func setupRemoteControls() {
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.addTarget { [weak self] _ in
      // Tell Flutter to play
      self?.sendCommandToFlutter("play")
      return .success
    }

    commandCenter.pauseCommand.addTarget { [weak self] _ in
      // Tell Flutter to pause
      self?.sendCommandToFlutter("pause")
      return .success
    }

    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.sendCommandToFlutter("toggle")
      return .success
    }

    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
  }

  func togglePiP() {
    // WKWebView handles PiP natively when allowsPictureInPictureMediaPlayback is true.
    // This method is reserved for future native PiP integration.
    // On iOS 14+, WKWebView automatically allows PiP for HTML5 video.
    // The JS-side PiP invocation is handled via enterMiniPlayerScript.
    print("PiP toggled from Flutter")
  }

  func sendCommandToFlutter(_ command: String) {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.mrplay/audio",
      binaryMessenger: controller.binaryMessenger
    )
    channel.invokeMethod("remoteControlEvent", arguments: command)
  }

  // Keep audio alive when app enters background
  override func applicationDidEnterBackground(_ application: UIApplication) {
    // Audio session stays active due to .playback category
    // WKWebView audio continues automatically
  }
}
