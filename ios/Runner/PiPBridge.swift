import AVFoundation
import AVKit
import Flutter
import Foundation
import UIKit

/// Attaches an AVPictureInPictureController to the AVPlayerLayer rendered by
/// video_player's platform view and exposes PiP control over the
/// `com.mrplay/pip` method channel.
class PiPBridge: NSObject, AVPictureInPictureControllerDelegate {
  static let shared = PiPBridge()

  private var channel: FlutterMethodChannel?
  private var pipController: AVPictureInPictureController?
  private var playerLayer: AVPlayerLayer?
  private var pipReadyObservation: NSKeyValueObservation?
  private var reportedReady = false
  private var prepareRetries = 0

  func attach(channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "prepare":
        self.prepare()
        result(nil)
      case "enterPiP":
        self.enterPiP()
        result(nil)
      case "exitPiP":
        self.exitPiP()
        result(nil)
      case "isPiPAvailable":
        result(self.pipController?.isPictureInPicturePossible ?? false)
      case "isPiPActive":
        result(self.pipController?.isPictureInPictureActive ?? false)
      case "clear":
        self.clear()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Releases the retained layer so PiP stops when the video is closed.
  func clear() {
    pipReadyObservation = nil
    reportedReady = false
    prepareRetries = 0
    pipController = nil
    playerLayer = nil
  }

  /// Links an [AVPictureInPictureController] to the current AVPlayerLayer
  /// WITHOUT starting PiP, and opts into automatic PiP when the app
  /// backgrounds. iOS then presents the floating window on home-screen
  /// swipe-off by itself — no synthetic commands needed.
  ///
  /// The layer lives in an always-mounted 1x1 host surface (so it survives the
  /// full/mini swap), but Flutter's platform view can take a layout pass before
  /// it exists, so this self-retries until the layer is found. Readiness is
  /// then reported to Dart through a KVO on `isPictureInPicturePossible`
  /// instead of a guessed delay.
  func prepare() {
    guard let layer = findPlayerLayer() else {
      prepareRetries += 1
      if prepareRetries > 40 { prepareRetries = 0; return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
        self?.prepare()
      }
      return
    }
    prepareRetries = 0
    if pipController == nil || pipController?.playerLayer !== layer {
      let controller = AVPictureInPictureController(playerLayer: layer)
      controller?.delegate = self
      if #available(iOS 15.0, *) {
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
      }
      pipController = controller
      // Retain the layer: the system needs it alive for PiP to continue.
      playerLayer = layer
    } else if #available(iOS 15.0, *) {
      pipController?.canStartPictureInPictureAutomaticallyFromInline = true
    }
    reportedReady = false
    pipReadyObservation = pipController?.observe(
      \.isPictureInPicturePossible, options: [.new]
    ) { [weak self] controller, _ in
      guard let self else { return }
      if controller.isPictureInPicturePossible {
        DispatchQueue.main.async { self.reportReadyOnce() }
      }
    }
  }

  private func reportReadyOnce() {
    guard !reportedReady else { return }
    reportedReady = true
    channel?.invokeMethod("pipReady", arguments: nil)
  }

  private func findPlayerLayer() -> AVPlayerLayer? {
    var found: AVPlayerLayer?
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        if let layer = findPlayerLayer(in: window) {
          found = layer
          break
        }
      }
      if found != nil { break }
    }
    return found
  }

  private func findPlayerLayer(in view: UIView) -> AVPlayerLayer? {
    if let layer = view.layer as? AVPlayerLayer, layer.player != nil {
      return layer
    }
    for subview in view.subviews {
      if let found = findPlayerLayer(in: subview) {
        return found
      }
    }
    return nil
  }

  func enterPiP() {
    guard let layer = findPlayerLayer() else { return }
    if pipController == nil || pipController?.playerLayer !== layer {
      let controller = AVPictureInPictureController(playerLayer: layer)
      controller?.delegate = self
      if #available(iOS 15.0, *) {
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
      }
      pipController = controller
      // Retain the layer: the Flutter surface is hidden when the mini player
      // collapses, and the system needs the layer alive for PiP to continue.
      playerLayer = layer
    }
    guard let controller = pipController else { return }
    if controller.isPictureInPicturePossible {
      controller.startPictureInPicture()
    } else {
      // The layer may need a moment to be attached to a window with content.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
        guard let self, let retry = self.pipController else { return }
        if retry.isPictureInPicturePossible {
          retry.startPictureInPicture()
        }
      }
    }
  }

  func exitPiP() {
    guard let controller = pipController else { return }
    if controller.isPictureInPictureActive {
      controller.stopPictureInPicture()
    }
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
    channel?.invokeMethod("pipStateChanged", arguments: "started")
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
    channel?.invokeMethod("pipStateChanged", arguments: "stopped")
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    channel?.invokeMethod("pipStateChanged", arguments: "restoreUI")
    completionHandler(true)
  }
}
