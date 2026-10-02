package com.example.api_manager

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * 网关前台服务：应用切后台/锁屏时保持进程存活。
 *
 * 背景：安卓会把后台应用冻结，导致本地网关"一退到后台就失效"。
 * 前台服务（常驻通知）+ 部分唤醒锁是系统允许的唯一正规做法——
 * 既让网关继续服务，也让用户明确知道"网关正在跑"（通知可点回应用）。
 */
class GatewayForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "apilot_gateway"
        const val NOTIFICATION_ID = 4787
        var running = false
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val port = intent?.getIntExtra("port", 8787) ?: 8787
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification(port))
        acquireWakeLock()
        running = true
        // 被杀后重启（系统允许时）。
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        try {
            wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        try {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "Apilot::GatewayWakeLock"
            )
            wakeLock?.acquire(24 * 60 * 60 * 1000L)
        } catch (_: Exception) {
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "本地网关",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "网关运行时的常驻提示（关闭网关后自动消失）"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(port: Int): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Apilot 网关运行中")
            .setContentText("端口 $port · 点击回到应用（关闭网关后本提示自动消失）")
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setOngoing(true)
            .setContentIntent(pending)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
