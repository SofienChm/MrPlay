package com.mrplay.app

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private var mediaChannel: MethodChannel? = null
  private var appChannel: MethodChannel? = null
  private var pendingShortcutUrl: String? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    pendingShortcutUrl = extractShortcutUrl(intent)
    super.onCreate(savedInstanceState)
    // Android 13+: the media notification (artwork, controls) is only shown once
    // the user has granted notification permission.
    if (Build.VERSION.SDK_INT >= 33 &&
        checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) {
      requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
    }
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.registerNativeAdFactory(
        flutterEngine, "mrplayNative", MrPlayNativeAdFactory(this))
    val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mrplay/media")
    mediaChannel = channel
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "setNowPlaying" -> {
          MediaSessionManager.setNowPlaying(this, call.arguments as? Map<*, *>)
          result.success(null)
        }
        "setPlaying" -> {
          MediaSessionManager.setPlaying(
              this, (call.arguments as? Map<*, *>)?.get("isPlaying") as? Boolean == true)
          result.success(null)
        }
        "clearNowPlaying" -> {
          MediaSessionManager.clearNowPlaying(this)
          result.success(null)
        }
        "setBackgroundAudioEnabled" -> {
          MediaSessionManager.setBackgroundAudioEnabled(this, call.arguments as? Boolean == true)
          result.success(null)
        }
        "enterPictureInPicture" -> {
          enterPiPMode()
          result.success(null)
        }
        "exitPictureInPicture" -> {
          // Android has no public exitPictureInPictureMode() API. Bring the
          // activity back to the foreground full-screen, which leaves PiP.
          try {
            val intent = Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP)
            startActivity(intent)
          } catch (_: Exception) {
            // Ignore — the user can still exit via the PiP window controls.
          }
          result.success(null)
        }
        "isInPictureInPicture" -> {
          result.success(isInPictureInPictureMode)
        }
        else -> result.notImplemented()
      }
    }
    MediaSessionManager.attach(channel)
    MediaSessionManager.ensureSession(this)

    // App shortcuts (long-press launcher icon) → `mrplay://open?url=...`.
    val appChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mrplay/app")
    this.appChannel = appChannel
    appChannel.setMethodCallHandler { call, result ->
      when (call.method) {
        "consumePendingUrl" -> {
          result.success(pendingShortcutUrl)
          pendingShortcutUrl = null
        }
        else -> result.notImplemented()
      }
    }
  }

  /** Pulls the target URL out of an `mrplay://open?url=...` shortcut intent. */
  private fun extractShortcutUrl(intent: Intent?): String? {
    val data = intent?.data ?: return null
    if (data.scheme != "mrplay") return null
    return data.getQueryParameter("url")
  }

  /** Handles shortcut taps while the app is already running. */
  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    extractShortcutUrl(intent)?.let { url ->
      pendingShortcutUrl = null
      try {
        appChannel?.invokeMethod("openUrl", url)
      } catch (_: RuntimeException) {
        // Flutter engine not ready yet — the pending URL path covers it.
      }
    }
  }

  /** Enters the system Picture-in-Picture overlay for the whole activity. */
  @Suppress("DEPRECATION")
  private fun enterPiPMode() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
        !packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
      return
    }
    val params = PictureInPictureParams.Builder()
        .setAspectRatio(Rational(16, 9))
        .build()
    enterPictureInPictureMode(params)
  }

  override fun onPictureInPictureModeChanged(
      isInPictureInPictureMode: Boolean, newConfig: Configuration) {
    super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      try {
        mediaChannel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
      } catch (_: RuntimeException) {
        // Flutter engine not ready yet — ignore.
      }
    }
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.unregisterNativeAdFactory(
        flutterEngine, "mrplayNative")
    super.cleanUpFlutterEngine(flutterEngine)
  }

  override fun onDestroy() {
    MediaSessionManager.clearNowPlaying(this)
    MediaSessionManager.release()
    super.onDestroy()
  }
}
