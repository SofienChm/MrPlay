package com.mrplay.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Base64
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.media.session.MediaButtonReceiver
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the Android [MediaSessionCompat] + media notification and drives a
 * foreground service while audio is playing. A foreground service is what keeps
 * the app process (and therefore the WebView's audio) alive in the background.
 */
object MediaSessionManager {
  const val NOTIFICATION_CHANNEL_ID = "mrplay_media"
  const val NOTIFICATION_ID = 1

  var channel: MethodChannel? = null
    private set
  var session: MediaSessionCompat? = null
    private set

  private var foregroundStarted = false
  private var lastTitle: String? = null
  private var lastArtist: String? = null
  private var lastDuration: Long = -1L
  private var lastArtwork: Bitmap? = null
  private var lastPlaying: Boolean? = null

  fun attach(channel: MethodChannel?) {
    this.channel = channel
  }

  fun ensureSession(context: Context) {
    if (session != null) return
    createNotificationChannel(context)

    val s = MediaSessionCompat(context, "MrPlay")
    s.setCallback(
        object : MediaSessionCompat.Callback() {
          override fun onPlay() = sendRemoteCommand("play")
          override fun onPause() = sendRemoteCommand("pause")
          override fun onSkipToNext() = sendRemoteCommand("skipForward")
          override fun onSkipToPrevious() = sendRemoteCommand("skipBackward")
          override fun onFastForward() = sendRemoteCommand("skipForward")
          override fun onRewind() = sendRemoteCommand("skipBackward")
          override fun onSeekTo(pos: Long) = sendRemoteCommand("seek", positionMs = pos.toDouble())
        })
    s.setFlags(
        MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
            MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
    s.isActive = true
    // Route headset / Bluetooth media buttons to this session.
    try {
      val buttonIntent = Intent(Intent.ACTION_MEDIA_BUTTON)
      buttonIntent.setClass(context, MediaButtonReceiver::class.java)
      s.setMediaButtonReceiver(
          PendingIntent.getBroadcast(
              context,
              0,
              buttonIntent,
              PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
    } catch (_: Exception) {
    }
    session = s
  }

  fun release() {
    session?.isActive = false
    session?.release()
    session = null
    foregroundStarted = false
  }

  fun isPlaying(): Boolean =
      session?.controller?.playbackState?.state == PlaybackStateCompat.STATE_PLAYING

  fun sendRemoteCommand(command: String, positionMs: Double? = null) {
    Log.d("MrPlay", "sendRemoteCommand: $command")
    val args = arrayListOf<Any>(command)
    if (positionMs != null) args.add(positionMs)
    if (Looper.myLooper() == Looper.getMainLooper()) {
      channel?.invokeMethod("remoteCommand", args)
    } else {
      Handler(Looper.getMainLooper()).post { channel?.invokeMethod("remoteCommand", args) }
    }
  }

  fun setNowPlaying(context: Context, args: Map<*, *>?) {
    val s = session ?: return
    if (args == null) return

    val existing = s.controller.metadata
    val title = args["title"] as? String ?: existing?.getString(MediaMetadataCompat.METADATA_KEY_TITLE)
    val artist = args["artist"] as? String ?: existing?.getString(MediaMetadataCompat.METADATA_KEY_ARTIST)
    val durationMs =
        (args["durationMs"] as? Number)?.toLong()
            ?: existing?.getLong(MediaMetadataCompat.METADATA_KEY_DURATION) ?: 0L
    val positionMs = (args["positionMs"] as? Number)?.toLong() ?: 0L
    val isPlaying = args["isPlaying"] as? Boolean == true
    val artwork = decodeArtwork(args["artwork"] as? String)
        ?: existing?.getBitmap(MediaMetadataCompat.METADATA_KEY_ART)

    // Only rewrite metadata when something actually changed (not every 1s
    // position tick); rebuilding MediaMetadata + the notification is what made
    // the app janky.
    val metaChanged =
        title != lastTitle || artist != lastArtist || durationMs != lastDuration || artwork !== lastArtwork
    if (metaChanged) {
      lastTitle = title
      lastArtist = artist
      lastDuration = durationMs
      lastArtwork = artwork
      val meta = MediaMetadataCompat.Builder()
      if (!title.isNullOrEmpty()) meta.putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
      if (!artist.isNullOrEmpty()) meta.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
      if (durationMs > 0) meta.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
      artwork?.let { meta.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, it) }
      s.setMetadata(meta.build())
    }

    updatePlaybackState(positionMs, durationMs, isPlaying)

    if (metaChanged || isPlaying != lastPlaying) {
      lastPlaying = isPlaying
      notify(context, buildNotification(context))
    }

    if (isPlaying) startForegroundService(context)
  }

  fun setPlaying(context: Context, isPlaying: Boolean) {
    val s = session ?: return
    val state = s.controller.playbackState
    val positionMs = state?.position ?: 0L
    val durationMs = s.controller.metadata?.getLong(MediaMetadataCompat.METADATA_KEY_DURATION) ?: 0L
    updatePlaybackState(positionMs, durationMs, isPlaying)
    if (isPlaying != lastPlaying) {
      lastPlaying = isPlaying
      notify(context, buildNotification(context))
    }
    if (isPlaying) startForegroundService(context)
  }

  fun clearNowPlaying(context: Context) {
    session?.setMetadata(null)
    session?.setPlaybackState(
        PlaybackStateCompat.Builder().setState(PlaybackStateCompat.STATE_NONE, 0, 0f).build())
    try {
      val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      nm.cancel(NOTIFICATION_ID)
    } catch (_: Exception) {
    }
    stopForegroundService(context)
    lastTitle = null
    lastArtist = null
    lastDuration = -1L
    lastArtwork = null
    lastPlaying = null
  }

  private fun updatePlaybackState(positionMs: Long, durationMs: Long, isPlaying: Boolean) {
    val s = session ?: return
    val b = PlaybackStateCompat.Builder()
    b.setActions(
        PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_SEEK_TO or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS)
    b.setState(
        if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
        positionMs,
        if (isPlaying) 1.0f else 0.0f)
    if (durationMs > 0) {
      b.setBufferedPosition(durationMs)
    }
    s.setPlaybackState(b.build())
  }

  fun buildNotification(context: Context): Notification {
    val s = session ?: throw IllegalStateException("MediaSession not created")
    val metadata = s.controller.metadata
    val title = metadata?.getString(MediaMetadataCompat.METADATA_KEY_TITLE)
    val artist = metadata?.getString(MediaMetadataCompat.METADATA_KEY_ARTIST)
    val artwork = metadata?.getBitmap(MediaMetadataCompat.METADATA_KEY_ART)
    val isPlaying = isPlaying()

    val contentIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    PendingIntent.FLAG_IMMUTABLE
                else 0)

    val icon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
    val label = if (isPlaying) "Pause" else "Play"
    val action = if (isPlaying) MediaActionReceiver.ACTION_PAUSE else MediaActionReceiver.ACTION_PLAY
    val actionPending =
        PendingIntent.getBroadcast(
            context,
            1,
            Intent(context, MediaActionReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    val builder =
        NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title ?: "MrPlay")
            .setContentText(artist ?: "")
            .setContentIntent(contentIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setOngoing(false)
            .addAction(NotificationCompat.Action.Builder(icon, label, actionPending).build())
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(s.sessionToken)
                    .setShowActionsInCompactView(0))
    artwork?.let { builder.setLargeIcon(it) }
    return builder.build()
  }

  private fun notify(context: Context, notification: Notification) {
    try {
      val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      nm.notify(NOTIFICATION_ID, notification)
    } catch (_: Exception) {
    }
  }

  private fun startForegroundService(context: Context) {
    if (foregroundStarted) return
    foregroundStarted = true
    Log.d("MrPlay", "startForegroundService")
    try {
      ContextCompat.startForegroundService(context, Intent(context, PlaybackService::class.java))
    } catch (e: Exception) {
      Log.e("MrPlay", "startForegroundService failed", e)
      foregroundStarted = false
    }
  }

  private fun stopForegroundService(context: Context) {
    if (!foregroundStarted) return
    foregroundStarted = false
    Log.d("MrPlay", "stopForegroundService")
    try {
      context.stopService(Intent(context, PlaybackService::class.java))
    } catch (_: Exception) {
    }
  }

  private fun createNotificationChannel(context: Context) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel =
          NotificationChannel(
              NOTIFICATION_CHANNEL_ID, "Playback", NotificationManager.IMPORTANCE_LOW)
      channel.description = "Now-playing controls and metadata"
      channel.setShowBadge(false)
      val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      nm.createNotificationChannel(channel)
    }
  }

  private fun decodeArtwork(base64: String?): Bitmap? {
    if (base64.isNullOrEmpty()) return null
    return try {
      val bytes = Base64.decode(base64, Base64.DEFAULT)
      BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    } catch (_: Exception) {
      null
    }
  }
}
