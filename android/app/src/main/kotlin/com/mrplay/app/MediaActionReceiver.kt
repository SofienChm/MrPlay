package com.mrplay.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles the play/pause buttons in the media notification. Dispatches through
 * the MediaSession transport controls so the command reaches Dart (and the
 * WebView) via the same path as lock-screen / headset buttons.
 */
class MediaActionReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val controls = MediaSessionManager.session?.controller?.transportControls ?: return
    when (intent.action) {
      ACTION_PLAY -> controls.play()
      ACTION_PAUSE -> controls.pause()
    }
  }

  companion object {
    const val ACTION_PLAY = "com.mrplay.app.action.PLAY"
    const val ACTION_PAUSE = "com.mrplay.app.action.PAUSE"
  }
}
