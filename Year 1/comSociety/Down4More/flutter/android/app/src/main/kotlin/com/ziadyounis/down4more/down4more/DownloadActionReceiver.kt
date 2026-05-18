package com.ziadyounis.down4more.down4more

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives notification-action broadcasts from the ongoing-download
 * notification owned by [DownloadForegroundService]. The only action we
 * surface today is "Cancel" — when the user taps it we route into
 * [YtDlpPlugin.cancelAllActiveDownloads] which fans the cancel out to
 * every in-flight `youtubedl-android` process.
 *
 * Registered as a non-exported `<receiver>` in the manifest so only our
 * own process can fire it.
 */
class DownloadActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_CANCEL_ALL -> {
                // Tell the plugin to cancel everything it knows about. The
                // plugin's per-coroutine `finally` blocks decrement the
                // active counter and stop the foreground service once the
                // last one exits, so we don't have to touch the service
                // directly from here.
                YtDlpPlugin.cancelAllActiveDownloads()
            }
        }
    }

    companion object {
        const val ACTION_CANCEL_ALL = "com.ziadyounis.down4more.action.CANCEL_ALL"
    }
}
