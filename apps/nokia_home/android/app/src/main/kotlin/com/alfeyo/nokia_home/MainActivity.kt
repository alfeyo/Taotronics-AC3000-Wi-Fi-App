package com.alfeyo.nokia_home

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var nokiaLocal: NokiaLocal? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        nokiaLocal = NokiaLocal(applicationContext)
        MethodChannel(messenger, "nokia_home/local")
            .setMethodCallHandler(nokiaLocal!!::handle)
        MethodChannel(messenger, "nokia_home/wifi_scan")
            .setMethodCallHandler(WifiScan(applicationContext)::handle)
    }

    override fun onDestroy() {
        nokiaLocal?.close()
        super.onDestroy()
    }
}
