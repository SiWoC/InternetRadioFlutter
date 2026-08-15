package nl.siwoc.internetradio

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Metadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.extractor.metadata.icy.IcyHeaders
import androidx.media3.extractor.metadata.icy.IcyInfo
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.extractor.metadata.vorbis.VorbisComment
import androidx.media3.session.MediaSession
import io.flutter.plugin.common.EventChannel
import kotlin.math.min

@UnstableApi
class RadioPlayerManager(context: Context) {
    private val appContext = context.applicationContext
    private var eventSink: EventChannel.EventSink? = null
    private var mediaSession: MediaSession? = null
    private var isMuted = false
    private var currentUrl: String? = null
    private var lastError: String? = null
    private var currentTitle: String? = null
    private var streamStationName: String? = null
    private var nowPlaying: String? = null

    private val handler = Handler(Looper.getMainLooper())
    private var retryAttempt = 0
    private var retryInSeconds: Int? = null
    private var retryAtElapsedMs: Long = 0
    private var retryRunnable: Runnable? = null
    private var countdownRunnable: Runnable? = null

    val player: ExoPlayer = createPlayer()

    private fun createPlayer(): ExoPlayer {
        val httpDataSourceFactory =
            DefaultHttpDataSource.Factory()
                .setUserAgent("InternetRadio/1.0 (Android)")
                .setConnectTimeoutMs(15_000)
                // Live streams can idle between chunks; avoid periodic reconnects.
                .setReadTimeoutMs(0)
                .setAllowCrossProtocolRedirects(true)
                .setDefaultRequestProperties(
                    mapOf(
                        IcyHeaders.REQUEST_HEADER_ENABLE_METADATA_NAME to
                            IcyHeaders.REQUEST_HEADER_ENABLE_METADATA_VALUE,
                    ),
                )

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
                            if (playbackState == Player.STATE_READY) {
                                lastError = null
                                resetRetry()
                            }
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
                            if (isTransientError(error) && currentUrl != null) {
                                scheduleRetry()
                            } else {
                                cancelRetry()
                                emitState()
                            }
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

                        override fun onTracksChanged(tracks: Tracks) {
                            for (groupIndex in 0 until tracks.groups.size) {
                                val group = tracks.groups[groupIndex]
                                for (trackIndex in 0 until group.length) {
                                    group.getTrackFormat(trackIndex).metadata?.let {
                                        applyMetadata(it)
                                    }
                                }
                            }
                        }

                        override fun onMetadata(metadata: Metadata) {
                            applyMetadata(metadata)
                        }

                        override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
                            val station =
                                mediaMetadata.station?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                            if (station != null && streamStationName != station) {
                                streamStationName = station
                                publishSessionMetadata()
                                emitState()
                            }
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
     * @param title Station display name for notification / MediaSession; blank uses default.
     * @return `true` when a stream was (re)started; `false` when [url] is already
     * active (noop). Failures are reported via [lastError] / MethodChannel errors.
     */
    fun play(url: String, title: String?, applyAudioRouteFix: Boolean): Boolean {
        if (url == currentUrl && player.playbackState != Player.STATE_IDLE) {
            player.playWhenReady = true
            emitState()
            return false
        }

        resetRetry()
        releaseCurrentStream()
        lastError = null
        currentUrl = url
        streamStationName = null
        nowPlaying = null

        val displayTitle = title?.takeIf { it.isNotBlank() } ?: DEFAULT_TITLE
        currentTitle = displayTitle
        player.setMediaItem(buildMediaItem(url, displayTitle))
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
        resetRetry()
        releaseCurrentStream()
        currentUrl = null
        currentTitle = null
        streamStationName = null
        nowPlaying = null
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
            put("retryInSeconds", retryInSeconds)
            put("bufferedPositionMs", player.bufferedPosition)
            put("totalBufferedDurationMs", player.totalBufferedDuration)
            put("streamStationName", streamStationName)
            put("nowPlaying", nowPlaying)
        }
    }

    /** Stream station name when the stream sends it, else the play() / JSON name. */
    fun sessionTitle(): String {
        return streamStationName?.takeIf { it.isNotEmpty() } ?: currentTitle ?: DEFAULT_TITLE
    }

    fun detach() {
        eventSink = null
    }

    fun release() {
        stop(stopService = true)
        player.release()
        eventSink = null
        mediaSession = null
    }

    private fun buildMediaItem(url: String, displayTitle: String): MediaItem {
        return MediaItem.Builder()
            .setUri(url)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(displayTitle)
                    .build(),
            )
            .setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setMinPlaybackSpeed(1f)
                    .setMaxPlaybackSpeed(1f)
                    .build(),
            )
            .build()
    }

    private fun releaseCurrentStream() {
        if (player.playbackState == Player.STATE_IDLE && player.mediaItemCount == 0) {
            return
        }
        player.stop()
        player.clearMediaItems()
    }

    private fun isTransientError(error: PlaybackException): Boolean {
        var cause: Throwable? = error
        while (cause != null) {
            if (cause is HttpDataSource.InvalidResponseCodeException) {
                val code = cause.responseCode
                return code == 408 || code == 429 || code in 500..599
            }
            cause = cause.cause
        }
        return when (error.errorCode) {
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
            PlaybackException.ERROR_CODE_TIMEOUT,
            PlaybackException.ERROR_CODE_IO_UNSPECIFIED,
            -> true
            else -> false
        }
    }

    private fun scheduleRetry() {
        cancelRetry()
        val shift = retryAttempt.coerceAtMost(MAX_BACKOFF_SHIFT)
        val delayMs = min(INITIAL_RETRY_DELAY_MS shl shift, MAX_RETRY_DELAY_MS)
        retryAtElapsedMs = SystemClock.elapsedRealtime() + delayMs
        retryInSeconds = ((delayMs + 999) / 1000).toInt()

        val retry =
            Runnable {
                performRetry()
            }
        retryRunnable = retry
        handler.postDelayed(retry, delayMs)

        val countdown =
            object : Runnable {
                override fun run() {
                    val remainingMs = retryAtElapsedMs - SystemClock.elapsedRealtime()
                    if (remainingMs <= 0) {
                        return
                    }
                    retryInSeconds = ((remainingMs + 999) / 1000).toInt()
                    emitState()
                    handler.postDelayed(this, 1_000)
                }
            }
        countdownRunnable = countdown
        handler.postDelayed(countdown, 1_000)

        Log.i(TAG, "Scheduling retry #$retryAttempt in ${retryInSeconds}s")
        emitState()
    }

    private fun performRetry() {
        val url = currentUrl ?: return
        val title = currentTitle ?: DEFAULT_TITLE
        retryRunnable = null
        countdownRunnable?.let { handler.removeCallbacks(it) }
        countdownRunnable = null
        retryInSeconds = null
        retryAttempt++

        Log.i(TAG, "Retrying stream (attempt=$retryAttempt): $url")
        releaseCurrentStream()
        player.setMediaItem(buildMediaItem(url, title))
        player.prepare()
        player.volume = if (isMuted) 0f else 1f
        player.playWhenReady = true
        emitState()
    }

    private fun cancelRetry() {
        retryRunnable?.let { handler.removeCallbacks(it) }
        countdownRunnable?.let { handler.removeCallbacks(it) }
        retryRunnable = null
        countdownRunnable = null
        retryInSeconds = null
    }

    private fun resetRetry() {
        cancelRetry()
        retryAttempt = 0
    }

    private fun applyMetadata(metadata: Metadata) {
        var stationName: String? = null
        var icyTitlePresent = false
        var icyTitle: String? = null
        var artist: String? = null
        var title: String? = null

        for (i in 0 until metadata.length()) {
            when (val entry = metadata[i]) {
                is IcyHeaders -> {
                    stationName = entry.name?.trim()?.takeIf { it.isNotEmpty() }
                }
                is IcyInfo -> {
                    icyTitlePresent = true
                    icyTitle = entry.title?.trim()?.takeIf { it.isNotEmpty() }
                }
                is TextInformationFrame -> {
                    val value = entry.values.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
                    when (entry.id) {
                        "TPE1", "TP1" -> artist = value
                        "TIT2", "TT2" -> title = value
                    }
                }
                is VorbisComment -> {
                    val value = entry.value.trim().takeIf { it.isNotEmpty() }
                    when (entry.key.uppercase()) {
                        "ARTIST" -> artist = value
                        "TITLE" -> title = value
                    }
                }
            }
        }

        var changed = false
        if (stationName != null && streamStationName != stationName) {
            streamStationName = stationName
            changed = true
        }
        if (icyTitlePresent) {
            if (nowPlaying != icyTitle) {
                nowPlaying = icyTitle
                changed = true
            }
        } else {
            val formatted = formatNowPlaying(artist, title)
            if (formatted != null && nowPlaying != formatted) {
                nowPlaying = formatted
                changed = true
            }
        }
        if (changed) {
            publishSessionMetadata()
            emitState()
        }
    }

    /** Now-playing line; omitted when it duplicates the station title. */
    private fun sessionArtist(): String? {
        val playing = nowPlaying?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        if (playing.equals(sessionTitle(), ignoreCase = true)) {
            return null
        }
        return playing
    }

    private fun publishSessionMetadata() {
        val index = player.currentMediaItemIndex
        if (index == C.INDEX_UNSET) {
            return
        }
        val item = player.getMediaItemAt(index)
        val title = sessionTitle()
        val artist = sessionArtist().orEmpty()
        val existing = item.mediaMetadata
        if (existing.title?.toString() == title &&
            existing.artist?.toString().orEmpty() == artist
        ) {
            return
        }
        val metadata =
            MediaMetadata.Builder()
                .setTitle(title)
                .setArtist(artist)
                .build()
        player.replaceMediaItem(
            index,
            item.buildUpon().setMediaMetadata(metadata).build(),
        )
        RadioPlaybackService.updateNotification(appContext)
    }

    private fun formatNowPlaying(artist: String?, title: String?): String? {
        val a = artist?.trim().orEmpty()
        val t = title?.trim().orEmpty()
        if (a.isEmpty() && t.isEmpty()) {
            return null
        }
        if (a.isEmpty()) {
            return t
        }
        if (t.isEmpty()) {
            return a
        }
        if (t.contains(a, ignoreCase = true)) {
            return t
        }
        return "$a - $t"
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
        private const val DEFAULT_TITLE = "Internet Radio"
        private const val INITIAL_RETRY_DELAY_MS = 1_000L
        private const val MAX_RETRY_DELAY_MS = 32_000L
        /** 2^5 * 1s = 32s; further attempts stay capped. */
        private const val MAX_BACKOFF_SHIFT = 5
    }
}
