import UIKit
import Flutter
import AVFoundation
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate {
  var audioSession: AVAudioSession?
  var audioChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    setupAudioSession()

    let controller = window?.rootViewController as! FlutterViewController
    audioChannel = FlutterMethodChannel(
      name: "com.mrplay/audio",
      binaryMessenger: controller.binaryMessenger
    )

    audioChannel?.setMethodCallHandler { [weak self] (call, result) in
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
      self?.sendCommandToFlutter("play")
      return .success
    }

    commandCenter.pauseCommand.addTarget { [weak self] _ in
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

  func sendCommandToFlutter(_ command: String) {
    DispatchQueue.main.async { [weak self] in
      self?.audioChannel?.invokeMethod("remoteControlEvent", arguments: command)
    }
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
  }
}
