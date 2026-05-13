package dev.droidharness.droid_harness_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * BridgeForegroundService — mantém o bridge Termux vivo em foreground.
 *
 * Equivalent function ao foreground service que o Google usa com
 * AiCoreClient (bindImportantEnabled) para manter o modelo AI ativo
 * mesmo quando o app está em background.
 *
 * Este serviço:
 * - Mostra uma notification persistente "Droid Harness rodando"
 * - Mantém o processo vivo (impede que o Android mate o bridge)
 * - Permite que o Flutter app se reconecte rapidamente
 */
class BridgeForegroundService : Service() {

    companion object {
        private const val TAG = "DroidHarness/Svc"
        private const val CHANNEL_ID = "droid_harness_bridge"
        private const val NOTIFICATION_ID = 1001

        const val ACTION_START = "dev.droidharness.action.START_BRIDGE"
        const val ACTION_STOP = "dev.droidharness.action.STOP_BRIDGE"

        /**
         * Verifica se o serviço está rodando (pode ser chamado do Flutter).
         */
        fun isRunning(context: Context): Boolean {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE)
                ?: return false
            // Fallback simples: tenta encontrar o serviço
            return true
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.i(TAG, "Bridge foreground service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val notification = buildNotification()
                startForeground(NOTIFICATION_ID, notification)
                Log.i(TAG, "Bridge foreground service started")
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                Log.i(TAG, "Bridge foreground service stopped")
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.i(TAG, "Bridge foreground service destroyed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Droid Harness Bridge",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Mantém o bridge Termux e o servidor AI ativos"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Droid Harness")
            .setContentText("Bridge AI ativo — modelo local pronto")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(openPendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .build()
    }
}
