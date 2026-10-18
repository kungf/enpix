package com.seephoto.see_photo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service whose only job is keeping the process alive while a
 * backup runs. The Flutter main isolate keeps executing in this process,
 * so the in-memory E2E session keys stay valid and the existing backup
 * pipeline continues when the app is backgrounded.
 *
 * Started/stopped from [MainActivity] via the `enpix/keepalive` channel.
 * START_NOT_STICKY: a restarted service without the Dart backup running
 * would be pointless.
 */
class BackupForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.backup_notification_channel),
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }

        val tapIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }
        return builder
            .setContentTitle(getString(R.string.backup_notification_title))
            .setContentText(getString(R.string.backup_notification_text))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(tapIntent)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "backup"
        private const val NOTIFICATION_ID = 1

        /**
         * Must be called while the app is foregrounded — Android 12+
         * forbids starting a foreground service from the background.
         */
        fun start(context: Context) {
            context.startForegroundService(
                Intent(context, BackupForegroundService::class.java)
            )
        }

        fun stop(context: Context) {
            context.stopService(
                Intent(context, BackupForegroundService::class.java)
            )
        }
    }
}
