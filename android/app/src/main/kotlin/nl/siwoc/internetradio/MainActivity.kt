package nl.siwoc.internetradio

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var radioPlayerPlugin: RadioPlayerPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        radioPlayerPlugin = RadioPlayerPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        radioPlayerPlugin?.dispose()
        radioPlayerPlugin = null
        super.onDestroy()
    }
}
