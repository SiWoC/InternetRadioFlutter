package nl.siwoc.internetradio

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.view.WindowManager

/**
 * Briefly turns the display on so the Player UI is visible after a remote command
 * while display policy allows the screen to sleep.
 */
object ScreenWake {
    private const val WAKE_MS = 3_000L
    private const val TAG = "internetradio:remoteWake"

    fun pulse(activity: Activity) {
        activity.runOnUiThread {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                activity.setTurnScreenOn(true)
            } else {
                @Suppress("DEPRECATION")
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
            }

            val powerManager =
                activity.getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            val wakeLock =
                powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    TAG,
                )
            wakeLock.acquire(WAKE_MS)
        }
    }
}
