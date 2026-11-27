package com.pocketcfo.app

import android.content.pm.ApplicationInfo
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val privacyChannel = "com.pocketcfo.app/privacy_screen"

    private val isDebuggableBuild: Boolean
        get() = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    /**
     * Bridges the Dart `setSecureScreen` privacy channel to Android `FLAG_SECURE`.
     *
     * Debuggable (`debug`/`profile`) builds skip `FLAG_SECURE` so emulator mirroring
     * (Android Studio Running Devices, scrcpy) and `adb screencap` stay visible during
     * `flutter run`; non-debuggable release builds enforce `FLAG_SECURE` strictly.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, privacyChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecureScreen" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val applySecure = enabled && !isDebuggableBuild
                        if (enabled && isDebuggableBuild) {
                            Log.i(
                                "PocketCFO",
                                "FLAG_SECURE skipped in debuggable build so emulator mirroring/screen capture stays visible; release builds enforce it.",
                            )
                        }
                        runOnUiThread {
                            if (applySecure) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
