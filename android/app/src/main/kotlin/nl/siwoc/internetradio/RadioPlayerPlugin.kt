package nl.siwoc.internetradio

import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class RadioPlayerPlugin(
    activity: Activity,
    messenger: BinaryMessenger,
) {
    private val playerManager = RadioPlayerManager(activity)
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    init {
        methodChannel.setMethodCallHandler(::onMethodCall)
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    playerManager.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    playerManager.setEventSink(null)
                }
            },
        )
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("invalid_argument", "url is required", null)
                    return
                }
                val applyAudioRouteFix = call.argument<Boolean>("applyAudioRouteFix") ?: true
                val started = playerManager.play(url, applyAudioRouteFix)
                result.success(playerManager.currentState(started = started))
            }
            "stop" -> {
                playerManager.stop()
                result.success(playerManager.currentState())
            }
            "setMuted" -> {
                val muted = call.argument<Boolean>("muted")
                if (muted == null) {
                    result.error("invalid_argument", "muted is required", null)
                    return
                }
                playerManager.setMuted(muted)
                result.success(playerManager.currentState())
            }
            "getState" -> result.success(playerManager.currentState())
            "retriggerAudioRouting" -> {
                playerManager.retriggerAudioRouting()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        playerManager.dispose()
    }

    companion object {
        const val METHOD_CHANNEL = "nl.siwoc.internetradio/radio_player"
        const val EVENT_CHANNEL = "nl.siwoc.internetradio/radio_player_events"
    }
}
