package nl.siwoc.internetradio

import android.content.Context

object RadioPlayerHolder {
    @Volatile
    private var instance: RadioPlayerManager? = null

    fun getInstance(context: Context): RadioPlayerManager {
        val existing = instance
        if (existing != null) {
            return existing
        }
        return synchronized(this) {
            instance ?: RadioPlayerManager(context.applicationContext).also { instance = it }
        }
    }
}
