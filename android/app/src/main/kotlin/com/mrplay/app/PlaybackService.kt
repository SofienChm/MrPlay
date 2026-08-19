package com.mrplay.app

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log

/**
 * Foreground service that keeps the app process (and the WebView's audio) alive
 * while media is playing. It holds the same media notification the app already
 * shows, promoted to foreground status.
 */
class PlaybackService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onCreate() {
    super.onCreate()
    Log.d("MrPlay", "PlaybackService.onCreate")
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    Log.d("MrPlay", "PlaybackService.onStartCommand")
    try {
      val notification = MediaSessionManager.buildNotification(this)
      startForeground(MediaSessionManager.NOTIFICATION_ID, notification)
    } catch (e: Exception) {
      Log.e("MrPlay", "PlaybackService failed to start foreground", e)
      stopSelf()
    }
    return START_NOT_STICKY
  }

  override fun onDestroy() {
    Log.d("MrPlay", "PlaybackService.onDestroy")
    stopForeground(STOP_FOREGROUND_REMOVE)
    super.onDestroy()
  }
}
