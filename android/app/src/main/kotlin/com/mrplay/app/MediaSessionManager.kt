package com.mrplay.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
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
  private var backgroundAudioEnabled = true
  private var lastTitle: String? = null
  private var lastArtist: String? = null
  private var lastDuration: Long = -1L
  private var lastArtwork: Bitmap? = null
  private var lastArtworkUrl: String? = null
  private var lastPlaying: Boolean? = null

  private var audioManager: AudioManager? = null
  private var deviceCallback: AudioDeviceCallback? = null
  private var noisyReceiver: BroadcastReceiver? = null
  private var appContext: Context? = null

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
    registerDeviceCallback(context)
    registerNoisyReceiver(context)
  }

  fun release() {
    try {
      appContext?.let { ctx ->
        noisyReceiver?.let { ctx.unregisterReceiver(it) }
      }
    } catch (_: Exception) {
    }
    noisyReceiver = null
    appContext = null
    deviceCallback?.let { audioManager?.unregisterAudioDeviceCallback(it) }
    deviceCallback = null
    audioManager = null
    session?.isActive = false
    session?.release()
    session = null
    foregroundStarted = false
    backgroundAudioEnabled = true
  }

  fun isPlaying(): Boolean =
      session?.controller?.playbackState?.state == PlaybackStateCompat.STATE_PLAYING

  /** Mirrors the "Background audio" toggle. When disabled the foreground
   *  service (which is what keeps the WebView audio alive in the background)
   *  must not run; Dart pauses the video when the app is backgrounded. */
  fun setBackgroundAudioEnabled(context: Context, enabled: Boolean) {
    backgroundAudioEnabled = enabled
    if (!enabled && foregroundStarted) {
      stopForegroundService(context)
    }
  }

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

    // Source of truth is our own cache (lastTitle/lastArtwork/...), NOT the
    // session's metadata read back: the round-trip can drop the bitmap or
    // duration, and the next rebuild would then erase them from the
    // notification / system media controls.
    val newTitle = args["title"] as? String
    val title = newTitle ?: lastTitle
    val artist = args["artist"] as? String ?: lastArtist
    val isNewTrack = newTitle != null && newTitle != lastTitle
    val reportedDuration = (args["durationMs"] as? Number)?.toLong() ?: 0L
    // A zero/invalid duration (page still loading, NaN) must not wipe a known
    // one for the same track.
    val durationMs =
        if (reportedDuration > 0) reportedDuration
        else if (isNewTrack) 0L
        else maxOf(lastDuration, 0L)
    val positionMs = (args["positionMs"] as? Number)?.toLong() ?: 0L
    val isPlaying = args["isPlaying"] as? Boolean == true
    val newArtwork = decodeArtwork(args["artwork"] as? String)
    val artwork = newArtwork ?: if (isNewTrack) null else lastArtwork
    val artworkUrl =
        (args["artworkUrl"] as? String)?.takeIf { it.isNotEmpty() }
            ?: if (isNewTrack) null else lastArtworkUrl

    val metaChanged =
        artworkUrl != lastArtworkUrl ||
        title != lastTitle ||
            artist != lastArtist ||
            durationMs != lastDuration ||
            newArtwork != null ||
            (isNewTrack && artwork == null)
    if (metaChanged) {
      lastTitle = title
      lastArtist = artist
      lastDuration = durationMs
      lastArtwork = artwork
      lastArtworkUrl = artworkUrl
      Log.d(
          "MrPlay",
          "setMetadata title=$title duration=$durationMs " +
              "art=${artwork?.let { "${it.width}x${it.height}" } ?: "none"} url=${artworkUrl != null}")
      val meta = MediaMetadataCompat.Builder()
      // Some System UI versions (stock-like ROMs) load the cover from a URI
      // instead of the bitmap, so provide both.
      artworkUrl?.let {
        meta.putString(MediaMetadataCompat.METADATA_KEY_ART_URI, it)
        meta.putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, it)
        meta.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI, it)
      }
      if (!title.isNullOrEmpty()) {
        meta.putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
        meta.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, title)
      }
      if (!artist.isNullOrEmpty()) {
        meta.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
        meta.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, artist)
      }
      // Always written (even 0) so the system keeps the key; >0 enables the
      // Android 13+ seek bar with elapsed / total time.
      meta.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, maxOf(durationMs, 0L))
      artwork?.let {
        meta.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, it)
        meta.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it)
        meta.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, it)
      }
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
    val durationMs = maxOf(lastDuration, 0L)
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
    lastArtworkUrl = null
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

  fun buildNotification(context: Context): Notification? {
    val s = session ?: return null
    val title = lastTitle
    val artist = lastArtist
    val artwork = lastArtwork
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

  private fun notify(context: Context, notification: Notification?) {
    if (notification == null) return
    try {
      val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      nm.notify(NOTIFICATION_ID, notification)
    } catch (_: Exception) {
    }
  }

  private fun startForegroundService(context: Context) {
    // "Background audio" is a user choice. Without the foreground service the
    // OS kills the WebView audio as soon as the app goes to the background —
    // which is exactly the "plain browser" behavior the toggle promises.
    if (!backgroundAudioEnabled) return
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

  /**
   * Pauses playback when a Bluetooth audio device (car, headset, earbuds) is
   * disconnected. `ACTION_AUDIO_BECOMING_NOISY` is the primary signal but is not
   * fired reliably for Bluetooth on every device, so we also watch
   * `AudioDeviceCallback` — the modern, permission-free signal for output-device
   * removal. Either path pauses unconditionally: the old `isPlaying()` gate was
   * a silent no-op whenever the MediaSession state was stale (the WebView plays
   * its own audio stream regardless), and pausing an already-paused video is
   * harmless.
   */
  private fun registerDeviceCallback(context: Context) {
    if (deviceCallback != null) return
    val am =
        context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return
    audioManager = am
    val cb =
        object : AudioDeviceCallback() {
          override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            val bluetoothGone = removedDevices.any { it.isBluetoothDevice() }
            if (bluetoothGone) {
              Log.d("MrPlay", "Bluetooth device removed — pausing")
              pausePlayback()
            }
          }
        }
    deviceCallback = cb
    am.registerAudioDeviceCallback(cb, Handler(Looper.getMainLooper()))
  }

  /**
   * Detects when audio output falls back to a noisier source — headphones
   * unplugged, or a Bluetooth car kit / earbuds disconnecting (exactly what
   * happens when you leave the car). The `audio_session` plugin also exposes
   * this stream, but it only works while the plugin holds audio focus and the
   * WebView's Chromium engine takes focus for itself, so it never fires here;
   * registering the system broadcast natively is the reliable path. Only the
   * system decides when output became noisy, so receiving it is unconditionally
   * the right moment to pause.
   */
  private fun registerNoisyReceiver(context: Context) {
    if (noisyReceiver != null) return
    appContext = context.applicationContext
    val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
    val receiver =
        object : BroadcastReceiver() {
          override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
              Log.d("MrPlay", "ACTION_AUDIO_BECOMING_NOISY — pausing")
              pausePlayback()
            }
          }
        }
    noisyReceiver = receiver
    ContextCompat.registerReceiver(
        context.applicationContext,
        receiver,
        filter,
        ContextCompat.RECEIVER_NOT_EXPORTED)
  }

  /** Sends the pause command to Dart, where the WebView video is actually
   *  stopped. Never gated: Dart's pause path is idempotent for a paused video. */
  private fun pausePlayback() {
    sendRemoteCommand("pause")
  }

  private fun AudioDeviceInfo.isBluetoothDevice(): Boolean =
      type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
          type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
          type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
          type == AudioDeviceInfo.TYPE_HEARING_AID

  private fun decodeArtwork(base64: String?): Bitmap? {
    if (base64.isNullOrEmpty()) return null
    return try {
      val bytes = Base64.decode(base64, Base64.DEFAULT)
      val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
      // Keep it well under the binder limit used to hand it to System UI.
      val maxSide = 512
      if (bmp.width > maxSide || bmp.height > maxSide) {
        val scale = maxSide.toFloat() / maxOf(bmp.width, bmp.height)
        Bitmap.createScaledBitmap(
            bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true)
      } else {
        bmp
      }
    } catch (_: Exception) {
      null
    }
  }
}
