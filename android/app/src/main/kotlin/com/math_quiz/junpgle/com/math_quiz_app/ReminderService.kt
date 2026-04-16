package com.math_quiz.junpgle.com.math_quiz_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * 极低功耗保活方案：
 *
 * ┌──────────────────────────────────────────────────────────────┐
 * │  设计原则：按需唤醒，用完即走，不常驻后台                          │
 * │                                                              │
 * │  1. App 首次启动 / 添加提醒 → Flutter 通知原生 scheduleReminders│
 * │  2. ReminderService 读取 SharedPreferences 里的提醒列表         │
 * │  3. 对每个未来提醒用 AlarmManager.setExactAndAllowWhileIdle 注册│
 * │  4. Alarm 触发 → ReminderAlarmReceiver → startForegroundService│
 * │  5. Service 发完通知后自动 stopSelf()，不常驻                    │
 * │  6. 开机 / 更新后 → BOOT_COMPLETED → 重新 scheduleReminders    │
 * └──────────────────────────────────────────────────────────────┘
 *
 * 功耗极低：仅在 Alarm 触发时短暂运行（< 2s），其余时间进程可被系统回收。
 */
class ReminderService : Service() {

    companion object {
        const val ACTION_SHOW_REMINDER = "com.math_quiz.SHOW_REMINDER"
        const val ACTION_RESCHEDULE    = "com.math_quiz.RESCHEDULE"
        const val TAG = "ReminderService"

        // SharedPreferences 键，Flutter 端写入，原生端读取
        const val PREFS_NAME    = "reminder_schedule"
        const val KEY_REMINDERS = "reminders_json"

        // 前台服务用的静默通知频道
        private const val FG_CHANNEL_ID   = "reminder_fg_service"
        private const val FG_NOTIFICATION_ID = 19999

        // 提醒通知频道（有声有震动，可同步手环）
        private const val REMINDER_CHANNEL_ID = "event_alert_v1"
    }

    private val executor = Executors.newSingleThreadExecutor()

    // ─────────────────────────────────────────────────────────────
    // Service 生命周期
    // ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 必须立刻调 startForeground，否则 Android 8+ 会 ANR
        startForeground(FG_NOTIFICATION_ID, buildSilentFgNotification())

        when (intent?.action) {
            ACTION_SHOW_REMINDER -> {
                val title = intent.getStringExtra("title") ?: "提醒"
                val text  = intent.getStringExtra("text")  ?: ""
                val notifId = intent.getIntExtra("notifId", 20000)
                val imagePath = intent.getStringExtra("analysis_image_path")
                executor.execute {
                    postReminderNotification(notifId, title, text, imagePath)
                    // 发完通知就结束，不常驻
                    stopSelf(startId)
                    // 顺手重新调度下一个 Alarm（因为 setExactAndAllowWhileIdle 只触发一次）
                    rescheduleAll()
                }
            }
            ACTION_RESCHEDULE -> {
                executor.execute {
                    rescheduleAll()
                    stopSelf(startId)
                }
            }
            else -> stopSelf(startId)
        }

        // START_NOT_STICKY：被杀后不自动重启，等下次 Alarm 或 Flutter 重新调度
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────
    // 核心：读取提醒列表并注册精确 Alarm
    // ─────────────────────────────────────────────────────────────

    private fun rescheduleAll() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json  = prefs.getString(KEY_REMINDERS, "[]") ?: "[]"

        try {
            val arr = JSONArray(json)
            val am  = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val now = System.currentTimeMillis()

            for (i in 0 until arr.length()) {
                val item = arr.getJSONObject(i)
                val triggerAtMs = item.getLong("triggerAtMs")
                val title       = item.optString("title", "提醒")
                val text        = item.optString("text", "")
                val notifId     = item.optInt("notifId", 20000 + i)
                val imagePath   = item.optString("analysisImagePath", "").takeIf { it.isNotBlank() }

                if (triggerAtMs <= now) continue   // 过期的跳过

                scheduleOneAlarm(am, triggerAtMs, title, text, notifId, imagePath)
            }
        } catch (e: Exception) {
            Log.e(TAG, "rescheduleAll parse error", e)
        }
    }

    private fun scheduleOneAlarm(
        am: AlarmManager,
        triggerAtMs: Long,
        title: String,
        text: String,
        notifId: Int,
        analysisImagePath: String?
    ) {
        val intent = Intent(this, ReminderAlarmReceiver::class.java).apply {
            action = ReminderAlarmReceiver.ACTION_FIRE
            putExtra("title", title)
            putExtra("text", text)
            putExtra("notifId", notifId)
            if (!analysisImagePath.isNullOrBlank()) {
                putExtra("analysis_image_path", analysisImagePath)
            }
        }
        val pi = PendingIntent.getBroadcast(
            this,
            notifId,                          // requestCode 用 notifId 区分不同提醒
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (am.canScheduleExactAlarms()) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                } else {
                    // 无精确闹钟权限：退回 setAndAllowWhileIdle（误差约 1 分钟，仍比无保活强）
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                }
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            }
        } catch (e: Exception) {
            Log.e(TAG, "scheduleOneAlarm error", e)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // 发出提醒通知
    // ─────────────────────────────────────────────────────────────

    private fun postReminderNotification(notifId: Int, title: String, text: String, analysisImagePath: String?) {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (!analysisImagePath.isNullOrBlank()) {
                putExtra("analysis_image_path", analysisImagePath)
            }
        }
        val pi = PendingIntent.getActivity(
            this, notifId, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = NotificationCompat.Builder(this, REMINDER_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pi)

        if (!analysisImagePath.isNullOrBlank()) {
            val viewImageIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("analysis_image_path", analysisImagePath)
            }
            val viewImagePi = PendingIntent.getActivity(
                this,
                notifId + 100000,
                viewImageIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            builder.addAction(0, "查看图片", viewImagePi)
        }

        val notification = builder.build()

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try { nm.notify(notifId, notification) } catch (e: Exception) {
            Log.e(TAG, "postReminderNotification error", e)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // 前台服务静默占位通知（用户几乎看不到，IMPORTANCE_MIN）
    // ─────────────────────────────────────────────────────────────

    private fun buildSilentFgNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, FG_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("CountDownTodo")
            .setContentText("正在调度提醒…")
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setContentIntent(pi)
            .build()
    }

    // ─────────────────────────────────────────────────────────────
    // 通知频道创建
    // ─────────────────────────────────────────────────────────────

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 前台服务占位频道：IMPORTANCE_MIN，完全静默，不出现在状态栏图标区
        if (nm.getNotificationChannel(FG_CHANNEL_ID) == null) {
            val ch = NotificationChannel(
                FG_CHANNEL_ID,
                "后台调度（不可见）",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "仅用于系统要求的前台服务占位，无任何提示"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            nm.createNotificationChannel(ch)
        }
    }
}

