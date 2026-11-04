package com.haryo.ai_video_clipper

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
 * STEP 17: foreground service agar proses panjang (transkripsi, render)
 * tetap hidup saat aplikasi dikirim ke latar belakang. Service ini TIDAK
 * mengerjakan apa pun; pekerjaan tetap berjalan di Dart/FFmpeg. Fungsinya
 * hanya menahan proses dan menampilkan notifikasi progres.
 */
class KeepAliveService : Service() {

    companion object {
        const val CHANNEL_ID = "processing"
        const val NOTIFICATION_ID = 4217
        const val ACTION_STOP = "com.haryo.ai_video_clipper.STOP_KEEP_ALIVE"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"

        fun build(context: Context, title: String, text: String, progress: Int): Notification {
            ensureChannel(context)
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pending = if (launch != null) {
                PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            } else null

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            builder
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(smallIcon(context))
                .setColor(0xFF1E2A78.toInt())
                .setOngoing(true)
                .setOnlyAlertOnce(true)
            if (pending != null) builder.setContentIntent(pending)
            if (progress in 0..100) {
                builder.setProgress(100, progress, false)
            } else {
                builder.setProgress(0, 0, true)
            }
            return builder.build()
        }

        /**
         * Ikon kecil notifikasi HARUS monokrom (putih di atas transparan).
         * Ikon peluncur berwarna/berlatar penuh akan tampil sebagai kotak.
         * Memakai drawable `ic_stat_clipper`; jika belum disalin, jatuh ke
         * ikon aplikasi.
         */
        private fun smallIcon(context: Context): Int {
            val id = context.resources.getIdentifier(
                "ic_stat_clipper", "drawable", context.packageName
            )
            return if (id != 0) id else context.applicationInfo.icon
        }

        /** Memperbarui notifikasi tanpa menyentuh service (aman dari latar belakang). */
        fun update(context: Context, title: String, text: String, progress: Int) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, build(context, title, text, progress))
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID, "Pemrosesan clip", NotificationManager.IMPORTANCE_LOW
                    )
                )
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "AI CLIPPER"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Memproses…"
        val notification = build(this, title, text, -1)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // Bila proses dimatikan sistem, jangan dihidupkan ulang tanpa pekerjaan.
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }
    }
}
