package com.mrplay.mrplay

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the process alive while YouTube audio plays
 * inside the WebView in the background.
 *
 * We do NOT request AudioFocus here. Chromium (the WebView) already holds
 * AudioFocus and is playing. If we requested AUDIOFOCUS_GAIN, Chromium's
 * AudioFocusDelegate would receive AUDIOFOCUS_LOSS (-1) and pause the video.
 *
 * All we need is the foreground service running so Android won't kill the
 * process. The WebView keeps playing on its own.
 */
class MediaPlaybackService : Service() {

    companion object {
        const val CHANNEL_ID      = "mrplay_playback"
        const val NOTIFICATION_ID = 101

        const val ACTION_START = "com.mrplay.START_PLAYBACK"
        const val ACTION_STOP  = "com.mrplay.STOP_PLAYBACK"
        const val EXTRA_TITLE  = "title"

        fun startIntent(context: Context, title: String = "MrPlay Audio"): Intent =
            Intent(context, MediaPlaybackService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
            }

        fun stopIntent(context: Context): Intent =
            Intent(context, MediaPlaybackService::class.java).apply {
                action = ACTION_STOP
            }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "MrPlay Audio"
                // Only start the foreground service — do NOT request AudioFocus.
                // Chromium holds focus; stealing it would pause the video.
                startForeground(NOTIFICATION_ID, buildNotification(title))
            }
        }
        return START_STICKY
    }

    private fun buildNotification(title: String): Notification {
        val openIntent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP }

        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        else
            PendingIntent.FLAG_UPDATE_CURRENT

        val contentPending = PendingIntent.getActivity(this, 0, openIntent, pendingFlags)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MrPlay")
            .setContentText(title)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(contentPending)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "MrPlay Background Audio",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps audio playing when app is in background"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
