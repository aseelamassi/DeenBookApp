package com.deenbook.deenbook

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Inexact local alarms; no exact alarm permission required. */
class SyncReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val verified = prefs.getLong("verified", 0L)
        val expiry = prefs.getLong("expiry", 0L)
        if (verified <= 0L || expiry <= verified) return
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) { scheduleFuture(context); return }
        if (intent.action != ACTION || intent.getLongExtra("verified", 0L) != verified ||
            intent.getLongExtra("expiry", 0L) != expiry) return
        val stage = intent.getIntExtra("stage", -1)
        if (stage !in 0..2 || prefs.getBoolean("sent$stage", false)) return
        val due = expiry - (2-stage) * DAY_MS
        if (due <= verified || System.currentTimeMillis() < due) return
        // If Android delivered an old reminder late, show only the latest stage.
        val remaining = expiry - System.currentTimeMillis()
        if (stage < 2 && remaining <= (1-stage)*DAY_MS) return
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "تذكيرات المزامنة", NotificationManager.IMPORTANCE_DEFAULT))
            val launch = PendingIntent.getActivity(context, 460, Intent(context, MainActivity::class.java), flags())
            val text = if (stage == 2) "انتهت مدة العمل دون إنترنت. اتصل بالخادم للمزامنة. عملياتك محفوظة."
                else "اقترب انتهاء مدة العمل دون إنترنت. زامن بياناتك الآن."
            @Suppress("DEPRECATION")
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
            manager.notify(470+stage, builder.setSmallIcon(android.R.drawable.ic_popup_sync)
                .setContentTitle("دفتر دين — تذكير المزامنة").setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text)).setContentIntent(launch).setAutoCancel(true).build())
            prefs.edit().putBoolean("sent$stage", true).apply()
        } catch (_: Exception) { /* Foreground warning remains available. */ }
    }
    companion object {
        private const val PREFS = "deenbook_sync_reminders"
        private const val CHANNEL = "deenbook_sync_reminders"
        private const val ACTION = "com.deenbook.deenbook.SYNC_REMINDER"
        private const val DAY_MS = 86_400_000L
        private fun flags(): Int = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        private fun alarmIntent(context: Context, stage: Int, verified: Long, expiry: Long): PendingIntent =
            PendingIntent.getBroadcast(context, 450+stage, Intent(context, SyncReminderReceiver::class.java).setAction(ACTION)
                .putExtra("stage", stage).putExtra("verified", verified).putExtra("expiry", expiry), flags())
        private fun alarm(context: Context) = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        fun cancel(context: Context) {
            for (stage in 0..2) {
                alarm(context).cancel(alarmIntent(context, stage, 0L, 0L))
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(470+stage)
            }
            // Cancel alarms from previous fixed-seven-day releases as well.
            for (day in 5..7) {
                alarm(context).cancel(alarmIntent(context, day, 0L, 0L))
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(470+day)
            }
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        }
        fun schedule(context: Context, verified: Long, days: Int, expires: Long) {
            val expiry = minOf(expires, verified + days * DAY_MS)
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getLong("verified", 0L) != verified || prefs.getLong("expiry", 0L) != expiry) {
                cancel(context)
                prefs.edit().putLong("verified", verified).putLong("expiry", expiry).apply()
            }
            if (expiry > verified) scheduleFuture(context)
        }
        private fun scheduleFuture(context: Context) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val verified = prefs.getLong("verified", 0L)
            val expiry = prefs.getLong("expiry", 0L)
            val now = System.currentTimeMillis()
            val latest = (0..2).lastOrNull { expiry - (2-it)*DAY_MS <= now }
            for (stage in 0..2) {
                val due = expiry - (2-stage)*DAY_MS
                if (due <= verified || prefs.getBoolean("sent$stage", false) || (due <= now && latest != stage)) continue
                alarm(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, maxOf(due, now+1000L),
                    alarmIntent(context, stage, verified, expiry))
            }
        }
    }
}
