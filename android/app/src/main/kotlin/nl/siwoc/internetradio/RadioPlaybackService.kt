package nl.siwoc.internetradio

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSession.ConnectionResult
import androidx.media3.session.MediaSession.ControllerInfo
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

@UnstableApi
class RadioPlaybackService : MediaSessionService() {
    private var mediaSession: MediaSession? = null
    private lateinit var playerManager: RadioPlayerManager

    override fun onCreate() {
        super.onCreate()
        playerManager = RadioPlayerHolder.getInstance(this)
        val session =
            MediaSession.Builder(this, playerManager.player)
                .setCallback(RadioMediaSessionCallback(playerManager))
                .build()
        mediaSession = session
        playerManager.attachMediaSession(session)
        setMediaNotificationProvider(
            DefaultMediaNotificationProvider.Builder(this)
                .setChannelId(NOTIFICATION_CHANNEL_ID)
                .build(),
        )
        setShowNotificationForIdlePlayer(SHOW_NOTIFICATION_FOR_IDLE_PLAYER_ALWAYS)
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_MUTE_TOGGLE -> playerManager.setMuted(!playerManager.isMuted())
            ACTION_STOP_PLAYBACK -> playerManager.stop(stopService = true)
        }

        // Must be called quickly after startForegroundService().
        promoteToForeground()
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onGetSession(controllerInfo: ControllerInfo): MediaSession? = mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        // If the user swipes the app away, stop audio to avoid "ghost playback" with no controls.
        playerManager.stop(stopService = true)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        playerManager.detachMediaSession()
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }

    private class RadioMediaSessionCallback(
        private val playerManager: RadioPlayerManager,
    ) : MediaSession.Callback {
        override fun onConnect(
            session: MediaSession,
            controller: ControllerInfo,
        ): ConnectionResult {
            val sessionCommands =
                ConnectionResult.DEFAULT_SESSION_COMMANDS.buildUpon()
                    .add(SessionCommand(ACTION_MUTE_TOGGLE, Bundle.EMPTY))
                    .add(SessionCommand(ACTION_STOP_PLAYBACK, Bundle.EMPTY))
                    .build()

            val builder =
                ConnectionResult.AcceptedResultBuilder(session)
                    .setAvailableSessionCommands(sessionCommands)

            if (session.isMediaNotificationController(controller)) {
                val playerCommands =
                    ConnectionResult.DEFAULT_PLAYER_COMMANDS.buildUpon()
                        .remove(Player.COMMAND_PLAY_PAUSE)
                        .remove(Player.COMMAND_SEEK_TO_PREVIOUS)
                        .remove(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                        .remove(Player.COMMAND_SEEK_TO_NEXT)
                        .remove(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
                        .build()
                builder
                    .setAvailablePlayerCommands(playerCommands)
                    .setMediaButtonPreferences(mediaButtons(playerManager.isMuted()))
            }

            return builder.build()
        }

        override fun onPostConnect(session: MediaSession, controller: ControllerInfo) {
            if (session.isMediaNotificationController(controller)) {
                session.setMediaButtonPreferences(mediaButtons(playerManager.isMuted()))
            }
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> {
            when (customCommand.customAction) {
                ACTION_MUTE_TOGGLE -> {
                    playerManager.setMuted(!playerManager.isMuted())
                    session.setMediaButtonPreferences(mediaButtons(playerManager.isMuted()))
                    return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }
                ACTION_STOP_PLAYBACK -> {
                    playerManager.stop(stopService = true)
                    return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }
            }
            return Futures.immediateFuture(SessionResult(SessionResult.RESULT_ERROR_NOT_SUPPORTED))
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel =
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                getString(R.string.radio_notification_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = getString(R.string.radio_notification_channel_description)
            }
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }

    private fun promoteToForeground() {
        val pendingMute =
            PendingIntent.getService(
                this,
                1,
                Intent(this, RadioPlaybackService::class.java).setAction(ACTION_MUTE_TOGGLE),
                PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag(),
            )

        val pendingStop =
            PendingIntent.getService(
                this,
                2,
                Intent(this, RadioPlaybackService::class.java).setAction(ACTION_STOP_PLAYBACK),
                PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag(),
            )

        val pendingDelete =
            PendingIntent.getService(
                this,
                3,
                Intent(this, RadioPlaybackService::class.java).setAction(ACTION_STOP_PLAYBACK),
                PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag(),
            )

        val title = playerManager.currentTitle() ?: getString(R.string.radio_default_title)
        val muteLabel =
            if (playerManager.isMuted()) {
                getString(R.string.radio_action_unmute)
            } else {
                getString(R.string.radio_action_mute)
            }
        val muteIcon =
            if (playerManager.isMuted()) {
                R.drawable.ic_radio_unmute
            } else {
                R.drawable.ic_radio_mute
            }

        val notification =
            NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setContentTitle(title)
                .setSmallIcon(R.drawable.ic_radio_notification)
                .setOngoing(true)
                .addAction(muteIcon, muteLabel, pendingMute)
                .addAction(R.drawable.ic_radio_stop, getString(R.string.radio_action_stop), pendingStop)
                .setDeleteIntent(pendingDelete)
                .setSilent(true)
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun pendingIntentImmutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }

    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "radio_playback"
        private const val NOTIFICATION_ID = DefaultMediaNotificationProvider.DEFAULT_NOTIFICATION_ID

        const val ACTION_MUTE_TOGGLE = "nl.siwoc.internetradio.action.MUTE_TOGGLE"
        const val ACTION_STOP_PLAYBACK = "nl.siwoc.internetradio.action.STOP_PLAYBACK"

        fun start(context: Context) {
            val intent = Intent(context, RadioPlaybackService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RadioPlaybackService::class.java))
        }

        fun mediaButtons(isMuted: Boolean): ImmutableList<CommandButton> {
            val muteButton =
                CommandButton.Builder()
                    .setDisplayName(
                        if (isMuted) {
                            "Unmute"
                        } else {
                            "Mute"
                        },
                    )
                    .setIconResId(
                        if (isMuted) {
                            R.drawable.ic_radio_unmute
                        } else {
                            R.drawable.ic_radio_mute
                        },
                    )
                    .setSessionCommand(SessionCommand(ACTION_MUTE_TOGGLE, Bundle.EMPTY))
                    .build()

            val stopButton =
                CommandButton.Builder()
                    .setDisplayName("Stop")
                    .setIconResId(R.drawable.ic_radio_stop)
                    .setSessionCommand(SessionCommand(ACTION_STOP_PLAYBACK, Bundle.EMPTY))
                    .build()

            return ImmutableList.of(muteButton, stopButton)
        }
    }
}
