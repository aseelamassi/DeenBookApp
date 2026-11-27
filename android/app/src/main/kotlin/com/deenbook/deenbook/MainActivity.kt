package com.deenbook.deenbook

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "deenbook/sync_reminders")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "schedule" -> {
                            val args = call.arguments as? Map<*, *>
                            val verified = (args?.get("verified") as? Number)?.toLong()
                            val days = (args?.get("days") as? Number)?.toInt()?.coerceIn(1, 7) ?: 7
                            val expires = (args?.get("expires") as? Number)?.toLong()
                            if (verified == null || verified <= 0L) {
                                result.error("bad_date", "Invalid verification time", null)
                            } else {
                                SyncReminderReceiver.schedule(this, verified, days, expires ?: (verified + days * 86_400_000L))
                                if (Build.VERSION.SDK_INT >= 33 &&
                                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                                    val prefs = getSharedPreferences("sync_reminder_permission", MODE_PRIVATE)
                                    if (!prefs.getBoolean("asked", false)) {
                                        prefs.edit().putBoolean("asked", true).apply()
                                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 451)
                                    }
                                }
                                result.success(null)
                            }
                        }
                        "cancel" -> { SyncReminderReceiver.cancel(this); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("notification_error", e.message, null)
                }
            }
    }
}
