package nl.siwoc.internetradio

import android.content.Context
import android.util.Log
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import io.flutter.plugin.common.EventChannel

class RadioPlayerManager(context: Context) {
    private val appContext = context.applicationContext
    private var eventSink: EventChannel.EventSink? = null
    private var mediaSession: MediaSession? = null
    private var isMuted = false
    private var currentUrl: String? = null
    private var lastError: String? = null
    private var currentTitle: String? = null

    val player: ExoPlayer = createPlayer()

    private fun createPlayer(): ExoPlayer {
        val httpDataSourceFactory =
            DefaultHttpDataSource.Factory()
                .setUserAgent("InternetRadio/1.0 (Android)")
                .setConnectTimeoutMs(15_000)
                // Live streams can idle between chunks; avoid periodic reconnects.
                .setReadTimeoutMs(0)
                .setAllowCrossProtocolRedirects(true)

        val dataSourceFactory =
            DefaultDataSource.Factory(appContext, httpDataSourceFactory)

        val loadControl =
            DefaultLoadControl.Builder()
                .setBufferDurationsMs(
                    20_000,
                    120_000,
                    1_000,
                    2_000,
                )
                .setPrioritizeTimeOverSizeThresholds(true)
                .setBackBuffer(0, false)
                .build()

        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)

        return ExoPlayer.Builder(appContext)
            .setMediaSourceFactory(mediaSourceFactory)
            .setLoadControl(loadControl)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build()
            .apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                        .build(),
                    true,
                )
                setHandleAudioBecomingNoisy(true)
                addListener(
                    object : Player.Listener {
                        override fun onPlaybackStateChanged(playbackState: Int) {
                            emitState()
                            if (playbackState == Player.STATE_IDLE && currentUrl == null) {
                                RadioPlaybackService.stop(appContext)
                            }
                        }

                        override fun onIsPlayingChanged(isPlaying: Boolean) {
                            emitState()
                        }

                        override fun onPlayerError(error: PlaybackException) {
                            lastError = error.message ?: error.errorCodeName
                            Log.w(TAG, "Player error: $lastError", error)
                            emitState()
                        }

                        override fun onPositionDiscontinuity(
                            oldPosition: Player.PositionInfo,
                            newPosition: Player.PositionInfo,
                            reason: Int,
                        ) {
                            Log.d(
                                TAG,
                                "Position discontinuity reason=$reason " +
                                    "old=${oldPosition.positionMs} new=${newPosition.positionMs}",
                            )
                        }
                    },
                )
            }
    }

    fun attachMediaSession(session: MediaSession) {
        mediaSession = session
    }

    fun detachMediaSession() {
        mediaSession = null
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        if (sink != null) {
            emitState()
        }
    }

    /**
     * @return `true` when a stream was (re)started; `false` when [url] is already
     * active (noop). Failures are reported via [lastError] / MethodChannel errors.
     */
    fun play(url: String, applyAudioRouteFix: Boolean): Boolean {
        if (url == currentUrl && player.playbackState != Player.STATE_IDLE) {
            player.playWhenReady = true
            emitState()
            return false
        }

        releaseCurrentStream()
        lastError = null
        currentUrl = url

        val title = titleForUrl(url)
        currentTitle = title
        val mediaItem =
            MediaItem.Builder()
                .setUri(url)
                .setMediaMetadata(
                    MediaMetadata.Builder()
                        .setTitle(title)
                        .setArtist("Internet Radio")
                        .build(),
                )
                .setLiveConfiguration(
                    MediaItem.LiveConfiguration.Builder()
                        .setMinPlaybackSpeed(1f)
                        .setMaxPlaybackSpeed(1f)
                        .build(),
                )
                .build()
        player.setMediaItem(mediaItem)
        player.prepare()
        player.volume = if (isMuted) 0f else 1f
        player.playWhenReady = true

        RadioPlaybackService.start(appContext)

        if (applyAudioRouteFix) {
            AudioRouteFixer.retriggerAudioRouting(appContext)
        }

        emitState()
        return true
    }

    fun stop(stopService: Boolean = true) {
        releaseCurrentStream()
        currentUrl = null
        currentTitle = null
        lastError = null
        emitState()
        if (stopService) {
            RadioPlaybackService.stop(appContext)
        }
    }

    fun setMuted(muted: Boolean) {
        if (isMuted == muted) {
            return
        }
        isMuted = muted
        player.volume = if (muted) 0f else 1f
        updateNotificationButtons()
        emitState()
    }

    fun isMuted(): Boolean = isMuted

    fun retriggerAudioRouting() {
        AudioRouteFixer.retriggerAudioRouting(appContext)
    }

    /** Snapshot for MethodChannel / EventChannel — playback state only (no call results). */
    fun currentState(): Map<String, Any?> {
        return buildMap {
            put("url", currentUrl)
            put("playbackState", playbackStateName(player.playbackState))
            put("isPlaying", player.isPlaying)
            put("isMuted", isMuted)
            put("error", lastError)
            put("bufferedPositionMs", player.bufferedPosition)
            put("totalBufferedDurationMs", player.totalBufferedDuration)
        }
    }

    fun currentTitle(): String? = currentTitle

    fun detach() {
        eventSink = null
    }

    fun release() {
        stop(stopService = true)
        player.release()
        eventSink = null
        mediaSession = null
    }

    private fun releaseCurrentStream() {
        if (player.playbackState == Player.STATE_IDLE && player.mediaItemCount == 0) {
            return
        }
        player.stop()
        player.clearMediaItems()
    }

    private fun titleForUrl(url: String): String {
        return when {
            url.contains("triplej", ignoreCase = true) -> "Triple J NSW"
            url.contains("alltimehits", ignoreCase = true) -> "All Time Hits"
            else -> "Internet Radio"
        }
    }

    private fun playbackStateName(state: Int): String {
        return when (state) {
            Player.STATE_IDLE -> "Idle"
            Player.STATE_BUFFERING -> "Buffering"
            Player.STATE_READY -> "Ready"
            Player.STATE_ENDED -> "Ended"
            else -> "Unknown"
        }
    }

    private fun emitState() {
        eventSink?.success(currentState())
    }

    private fun updateNotificationButtons() {
        mediaSession?.setMediaButtonPreferences(RadioPlaybackService.mediaButtons(isMuted))
    }

    companion object {
        private const val TAG = "RadioPlayerManager"
    }
}
