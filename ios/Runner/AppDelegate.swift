import UIKit
import Flutter
import AVFoundation
import WebKit
import CoreSpotlight
import UniformTypeIdentifiers

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var spotlightChannel: FlutterMethodChannel?

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

    setupSpotlightChannel()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
}
