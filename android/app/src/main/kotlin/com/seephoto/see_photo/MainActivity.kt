package com.seephoto.see_photo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Keepalive channel — see lib/services/background/backup_keepalive.dart.
        // "start" launches the backup foreground service that keeps the
        // process (and the running backup) alive in the background.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "enpix/keepalive",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    BackupForegroundService.start(this)
                    result.success(null)
                }
                "stop" -> {
                    BackupForegroundService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
