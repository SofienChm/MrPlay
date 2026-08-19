package com.mrplay.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mrplay/media")
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
        else -> result.notImplemented()
      }
    }
    MediaSessionManager.attach(channel)
    MediaSessionManager.ensureSession(this)
  }

  override fun onDestroy() {
    MediaSessionManager.clearNowPlaying(this)
    MediaSessionManager.release()
    super.onDestroy()
  }
}
