package dev.droidharness.droid_harness_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BootReceiver — inicia o foreground service do Droid Harness
 * quando o dispositivo Android é ligado (BOOT_COMPLETED).
 *
 * Equivalente ao RECEIVE_BOOT_COMPLETED que o Google usa no Edge Gallery
 * para retomar serviços de IA após reboot.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "DroidHarness/Boot"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON" &&
            intent.action != "com.htc.intent.action.QUICKBOOT_POWERON") {
            return
        }

        Log.i(TAG, "Boot completed — starting Droid Harness bridge service")

        try {
            val serviceIntent = Intent(context, BridgeForegroundService::class.java)
            serviceIntent.action = BridgeForegroundService.ACTION_START

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start bridge service on boot", e)
        }
    }
}
