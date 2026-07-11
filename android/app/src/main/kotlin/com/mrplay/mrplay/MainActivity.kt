package com.mrplay.mrplay

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.mrplay/background_playback"
    private var methodChannel: MethodChannel? = null
    private var keepWebViewAlive = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        val title = call.argument<String>("title") ?: "MrPlay Audio"
                        keepWebViewAlive = true
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(MediaPlaybackService.startIntent(this@MainActivity, title))
                        } else {
                            startService(MediaPlaybackService.startIntent(this@MainActivity, title))
                        }
                        result.success(null)
                    }
                    "stopForegroundService" -> {
                        keepWebViewAlive = false
                        startService(MediaPlaybackService.stopIntent(this@MainActivity))
                        result.success(null)
                    }
                    "enterPip" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                                .build()
                            enterPictureInPictureMode(params)
                        }
                        result.success(null)
                    }
                    "moveTaskToBack" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onPause() {
        super.onPause()
        if (keepWebViewAlive) {
            resumeAllWebViews()
        }
    }

    override fun onStop() {
        super.onStop()
        if (keepWebViewAlive) {
            resumeAllWebViews()
        }
    }

    override fun onResume() {
        super.onResume()
        resumeAllWebViews()
    }

    private fun resumeAllWebViews() {
        fun walk(view: View) {
            val className = view.javaClass.name
            // Target any system or custom wrapper webview engine container safely
            if (className.contains("WebView", ignoreCase = true)) {
                try {
                    view.javaClass.getMethod("onResume").invoke(view)
                    view.javaClass.getMethod("resumeTimers").invoke(view)
                } catch (e: Exception) {}
            }
            if (view is ViewGroup) {
                for (i in 0 until view.childCount) walk(view.getChildAt(i))
            }
        }
        window.decorView.let { walk(it) }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
    }
}
