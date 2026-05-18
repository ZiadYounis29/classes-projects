package com.ziadyounis.down4more.down4more

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
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the OS from killing the app while a
 * download is in flight (screen off, app backgrounded, low-memory pressure).
 *
 * Lifecycle is driven by [YtDlpPlugin]:
 * - First `startDownload` call → [start] (count = 1).
 * - Subsequent `startDownload` calls → [start] (count incremented).
 * - Last download finishes / is cancelled → [stop].
 *
 * Per-download progress is shown in the Flutter UI, not the notification —
 * a single aggregate "N download(s) in progress" notification keeps the
 * shade quiet when several downloads are queued at once.
 *
 * The notification exposes two affordances:
 *  - Tap the body → brings `MainActivity` back to the foreground so the
 *    user can see live per-download progress.
 *  - Tap the "Cancel" action → broadcasts to [DownloadActionReceiver],
 *    which calls into [YtDlpPlugin.cancelAllActiveDownloads] to abort
 *    every in-flight download. The service stops itself once the active
 *    counter hits zero in [YtDlpPlugin.onDownloadFinished].
 *
 * On API ≥ 34 (Android 14, `UPSIDE_DOWN_CAKE`) the service must declare a
 * `foregroundServiceType` and the app must hold a matching typed permission
 * (`FOREGROUND_SERVICE_DATA_SYNC` for our case). Both are declared in
 * `AndroidManifest.xml`.
 */
class DownloadForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val active = (intent?.getIntExtra(EXTRA_ACTIVE, 1) ?: 1).coerceAtLeast(1)
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Down4More"
        val text = intent?.getStringExtra(EXTRA_TEXT)
            ?: if (active == 1) "1 download in progress" else "$active downloads in progress"
        startForegroundCompat(buildNotification(title, text))
        return START_STICKY
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(title: String, text: String): Notification {
        ensureChannel()
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_download)
            .setContentIntent(buildContentIntent())
            .addAction(0, "Cancel", buildCancelIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .build()
    }

    /**
     * PendingIntent that brings the existing Flutter activity back to the
     * foreground when the user taps the notification body. `singleTop` +
     * `FLAG_ACTIVITY_CLEAR_TOP` mean we never spawn a second copy of the
     * app — the running engine and its download state stay intact.
     */
    private fun buildContentIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent().apply { setClassName(packageName, "$packageName.MainActivity") }
        launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            this,
            REQ_CONTENT,
            launch,
            pendingIntentFlags(),
        )
    }

    /**
     * PendingIntent that fires [DownloadActionReceiver.ACTION_CANCEL_ALL]
     * when the user taps the "Cancel" action chip.
     */
    private fun buildCancelIntent(): PendingIntent {
        val intent = Intent(this, DownloadActionReceiver::class.java).apply {
            action = DownloadActionReceiver.ACTION_CANCEL_ALL
            setPackage(packageName)
        }
        return PendingIntent.getBroadcast(
            this,
            REQ_CANCEL,
            intent,
            pendingIntentFlags(),
        )
    }

    /**
     * API 31+ requires every PendingIntent to be either immutable or
     * mutable explicitly. We never mutate ours, so immutable everywhere.
     */
    private fun pendingIntentFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            CHANNEL_ID,
            "Downloads",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shown while downloads are running so Android doesn't kill the app."
            setShowBadge(false)
        }
        mgr.createNotificationChannel(ch)
    }

    companion object {
        private const val NOTIFICATION_ID = 4201
        private const val CHANNEL_ID = "down4more.downloads"

        private const val EXTRA_ACTIVE = "active"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"

        private const val REQ_CONTENT = 1
        private const val REQ_CANCEL = 2

        /**
         * Start (or update) the foreground service so it reflects [active]
         * concurrent downloads. Safe to call repeatedly — Android will just
         * deliver a new `onStartCommand` to the running service.
         */
        fun start(context: Context, active: Int) {
            val intent = Intent(context, DownloadForegroundService::class.java).apply {
                putExtra(EXTRA_ACTIVE, active)
                putExtra(EXTRA_TITLE, "Down4More")
                putExtra(
                    EXTRA_TEXT,
                    if (active == 1) "1 download in progress"
                    else "$active downloads in progress",
                )
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Throwable) {
                // BackgroundServiceStartNotAllowedException (API 31+) can fire
                // if the app gets backgrounded between starting a download and
                // the service launching. The download itself still runs — the
                // OS may just kill it sooner. Best-effort: swallow and move on.
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, DownloadForegroundService::class.java))
            } catch (_: Throwable) { /* already stopped — fine */ }
        }
    }
}
