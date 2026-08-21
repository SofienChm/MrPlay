import UIKit
import Flutter
import AVFoundation
import WebKit
import CoreSpotlight
import UniformTypeIdentifiers
import MediaPlayer

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var spotlightChannel: FlutterMethodChannel?
  private var mediaChannel: FlutterMethodChannel?
  private var siriChannel: FlutterMethodChannel?
  private var shortcutActivities: [String: NSUserActivity] = [:]
  private var routeChangeObserver: NSObjectProtocol?

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

    observeAudioRouteChanges()

    setupSpotlightChannel()
    setupMediaChannel()
    setupSiriChannel()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// When the user disconnects the Bluetooth device (or unplugs headphones),
  /// stop playback instead of blasting audio from the speaker. Reuses the
  /// remote-command pipeline so player state and Now Playing stay in sync.
  private func observeAudioRouteChanges() {
    routeChangeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let info = notification.userInfo,
            let reasonRaw = (info[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue,
            reasonRaw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else {
        return
      }
      guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
      self?.sendRemoteCommand("pause")
    }
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
    if userActivity.activityType == "com.mrplay.app.openPlatform",
       let url = userActivity.userInfo?["url"] as? String {
      handleShortcutUrl(url)
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

  // MARK: - Siri shortcuts (NSUserActivity)

  private func setupSiriChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "com.mrplay/siri", binaryMessenger: controller.binaryMessenger)
    siriChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "register":
        if let args = call.arguments as? [String: Any],
           let list = args["shortcuts"] as? [[String: Any]] {
          for item in list {
            if let id = item["id"] as? String,
               let title = item["title"] as? String,
               let url = item["url"] as? String {
              self.makeActivity(id: id, title: title, url: url)
            }
          }
        }
        result(nil)
      case "setCurrent":
        if let args = call.arguments as? [String: Any],
           let name = args["name"] as? String,
           let url = args["url"] as? String {
          self.makeActivity(id: "current", title: "Open \(name) in MrPlay", url: url)
        }
        result(nil)
      case "consumePending":
        let pending = UserDefaults.standard.string(forKey: "pendingShortcutUrl")
        if pending != nil {
          UserDefaults.standard.removeObject(forKey: "pendingShortcutUrl")
        }
        result(pending)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func makeActivity(id: String, title: String, url: String) {
    let activity = NSUserActivity(activityType: "com.mrplay.app.openPlatform")
    activity.persistentIdentifier = id
    activity.title = title
    activity.userInfo = ["url": url]
    activity.isEligibleForSearch = true
    activity.isEligibleForPrediction = true
    shortcutActivities[id] = activity
    activity.becomeCurrent()
  }

  private func handleShortcutUrl(_ url: String) {
    UserDefaults.standard.set(url, forKey: "pendingShortcutUrl")
    siriChannel?.invokeMethod("onShortcut", arguments: ["url": url])
  }

  // MARK: - Media controls (Control Center / Lock Screen)

  private func setupMediaChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "com.mrplay/media", binaryMessenger: controller.binaryMessenger)
    mediaChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "setNowPlaying":
        if let args = call.arguments as? [String: Any] {
          self.setNowPlaying(args)
        }
        result(nil)
      case "setPlaying":
        if let playing = (call.arguments as? [String: Any])?["isPlaying"] as? Bool {
          self.setPlaying(playing)
        }
        result(nil)
      case "clearNowPlaying":
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    setupRemoteCommands()
  }

  private func setNowPlaying(_ info: [String: Any]) {
    var now = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

    if let title = info["title"] as? String {
      now[MPMediaItemPropertyTitle] = title
    }
    if let artist = info["artist"] as? String {
      now[MPMediaItemPropertyArtist] = artist
    }
    if let durationMs = (info["durationMs"] as? NSNumber)?.doubleValue {
      now[MPMediaItemPropertyPlaybackDuration] = durationMs / 1000.0
    }
    if let positionMs = (info["positionMs"] as? NSNumber)?.doubleValue {
      now[MPNowPlayingInfoPropertyElapsedPlaybackTime] = positionMs / 1000.0
    }
    now[MPNowPlayingInfoPropertyPlaybackRate] = ((info["isPlaying"] as? Bool) ?? false) ? 1.0 : 0.0
    if let base64 = info["artwork"] as? String,
       let data = Data(base64Encoded: base64),
       let image = UIImage(data: data) {
      now[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = now
  }

  private func setPlaying(_ playing: Bool) {
    guard var now = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
    now[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = now
  }

  private func setupRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()

    center.playCommand.isEnabled = true
    center.playCommand.addTarget { [weak self] _ in
      self?.sendRemoteCommand("play")
      return .success
    }

    center.pauseCommand.isEnabled = true
    center.pauseCommand.addTarget { [weak self] _ in
      self?.sendRemoteCommand("pause")
      return .success
    }

    center.togglePlayPauseCommand.isEnabled = true
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.sendRemoteCommand("toggle")
      return .success
    }

    center.skipForwardCommand.isEnabled = true
    center.skipForwardCommand.preferredIntervals = [15]
    center.skipForwardCommand.addTarget { [weak self] _ in
      self?.sendRemoteCommand("skipForward")
      return .success
    }

    center.skipBackwardCommand.isEnabled = true
    center.skipBackwardCommand.preferredIntervals = [15]
    center.skipBackwardCommand.addTarget { [weak self] _ in
      self?.sendRemoteCommand("skipBackward")
      return .success
    }

    center.changePlaybackPositionCommand.isEnabled = true
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let commandEvent = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      self?.sendRemoteCommand("seek", positionMs: commandEvent.positionTime * 1000.0)
      return .success
    }
  }

  private func sendRemoteCommand(_ command: String, positionMs: Double? = nil) {
    var arguments: [Any] = [command]
    if let positionMs {
      arguments.append(positionMs)
    }
    mediaChannel?.invokeMethod("remoteCommand", arguments: arguments)
  }
}