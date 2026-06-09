package com.math_quiz.junpgle.com.math_quiz_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.github.d4viddf.hyperisland_kit.HyperIslandNotification
import io.github.d4viddf.hyperisland_kit.HyperPicture
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * 单 Alarm 滚动调度方案：
 *
 * ┌──────────────────────────────────────────────────────────────┐
 * │  设计原则：系统同时只维护一个最近提醒的 Alarm                     │
 * │                                                              │
 * │  1. App 首次启动 / 添加提醒 → Flutter 通知原生 scheduleReminders│
 * │  2. ReminderService 读取 SharedPreferences 里的提醒列表         │
 * │  3. 只找 triggerAtMs 最近的未来提醒，注册一个精确 Alarm          │
 * │  4. Alarm 触发 → ReminderAlarmReceiver → startForegroundService│
 * │  5. Service 发完通知后重新读取列表，注册下一个最近提醒            │
 * │  6. 如此滚动，系统中始终只有一个 Alarm                          │
 * │  7. 开机 / 更新后 → BOOT_COMPLETED → 重新 scheduleReminders    │
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
        private const val LIVE_CHANNEL_ID = "live_updates_official_v2"
        private const val TODO_ISLAND_BIZ_TAG = "math_quiz_todo"
        private const val COURSE_ISLAND_BIZ_TAG = "math_quiz_course"
        private const val SPECIAL_TODO_ISLAND_BIZ_TAG = "math_quiz_special_todo"

        // 单 Alarm 滚动调度：固定 requestCode
        private const val ROLLING_ALARM_REQUEST_CODE = 0xCD7001
    }

    private val executor = Executors.newSingleThreadExecutor()

    // ─────────────────────────────────────────────────────────────
    // Service 生命周期
    // ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createChannels()
        // 🚀 核心修复：Android 14+ 要求在 onCreate 中尽快开启前台服务，且必须指定类型
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else {
                0
            }
            try {
                startForeground(FG_NOTIFICATION_ID, buildSilentFgNotification(), type)
            } catch (e: Exception) {
                Log.e(TAG, "startForeground error in onCreate", e)
                // 兜底调用
                startForeground(FG_NOTIFICATION_ID, buildSilentFgNotification())
            }
        } else {
            startForeground(FG_NOTIFICATION_ID, buildSilentFgNotification())
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // onCreate 已调用过，这里双重保险（注意：Android 12+ 允许在 onStartCommand 调用）

        when (intent?.action) {
            ACTION_SHOW_REMINDER -> {
                val title = intent.getStringExtra("title") ?: "提醒"
                val text  = intent.getStringExtra("text")  ?: ""
                val notifId = intent.getIntExtra("notifId", 20000)
                Log.d(TAG, "RollingAlarm: ACTION_FIRE received, notifId = $notifId, title = $title")
                val imagePath = intent.getStringExtra("analysis_image_path")
                val type = intent.getStringExtra("type")
                val todoType = intent.getStringExtra("todo_type")
                val courseName = intent.getStringExtra("course_name")
                val room = intent.getStringExtra("room")
                val timeStr = intent.getStringExtra("time_str")
                val teacher = intent.getStringExtra("teacher")
                val originalText = intent.getStringExtra("original_text")
                val planBlockId = intent.getStringExtra("plan_block_id")
                val todoId = intent.getStringExtra("todo_id")
                executor.execute {
                    postReminderNotification(
                        notifId = notifId,
                        title = title,
                        text = text,
                        analysisImagePath = imagePath,
                        type = type,
                        todoType = todoType,
                        courseName = courseName,
                        room = room,
                        timeStr = timeStr,
                        teacher = teacher,
                        originalText = originalText,
                        planBlockId = planBlockId,
                        todoId = todoId
                    )
                    // 发完通知就结束，不常驻
                    stopSelf(startId)
                    // 滚动调度：注册下一个最近提醒
                    Log.d(TAG, "RollingAlarm: notification posted, reschedule next")
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
    // 核心：单 Alarm 滚动调度
    // ─────────────────────────────────────────────────────────────

    private fun rescheduleAll() {
        Log.d(TAG, "RollingAlarm: rescheduleAll start")
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json  = prefs.getString(KEY_REMINDERS, "[]") ?: "[]"

        try {
            val arr = JSONArray(json)
            val now = System.currentTimeMillis()

            Log.d(TAG, "RollingAlarm: loaded reminders count = ${arr.length()}")

            cancelRollingAlarm()

            val nextItem = findNextFutureReminder(arr, now)

            if (nextItem != null) {
                val triggerAtMs = nextItem.getLong("triggerAtMs")
                val notifId = nextItem.optInt("notifId", -1)
                val title = nextItem.optString("title", "提醒")
                val date = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
                    .format(java.util.Date(triggerAtMs))
                Log.d(TAG, "RollingAlarm: next trigger = $date, notifId = $notifId, title = $title")
                scheduleRollingAlarm(nextItem)
            } else {
                Log.d(TAG, "RollingAlarm: no future reminders")
            }
        } catch (e: Exception) {
            Log.e(TAG, "RollingAlarm: rescheduleAll parse error", e)
        }
    }

    private fun findNextFutureReminder(arr: JSONArray, now: Long): JSONObject? {
        var next: JSONObject? = null
        var nextTime = Long.MAX_VALUE

        for (i in 0 until arr.length()) {
            val item = arr.getJSONObject(i)
            val triggerAtMs = item.optLong("triggerAtMs", -1L)
            if (triggerAtMs > now && triggerAtMs < nextTime) {
                next = item
                nextTime = triggerAtMs
            }
        }

        return next
    }

    private fun scheduleRollingAlarm(item: JSONObject) {
        val triggerAtMs = item.getLong("triggerAtMs")
        val intent = Intent(this, ReminderAlarmReceiver::class.java).apply {
            action = ReminderAlarmReceiver.ACTION_FIRE
            setPackage(packageName)

            putExtra("title", item.optString("title", "提醒"))
            putExtra("text", item.optString("text", ""))
            putExtra("notifId", item.optInt("notifId", 20000))

            item.optString("type", "").takeIf { it.isNotBlank() }?.let {
                putExtra("type", it)
            }
            item.optString("todoType", "").takeIf { it.isNotBlank() }?.let {
                putExtra("todo_type", it)
            }
            item.optString("courseName", "").takeIf { it.isNotBlank() }?.let {
                putExtra("course_name", it)
            }
            item.optString("room", "").takeIf { it.isNotBlank() }?.let {
                putExtra("room", it)
            }
            item.optString("timeStr", "").takeIf { it.isNotBlank() }?.let {
                putExtra("time_str", it)
            }
            item.optString("teacher", "").takeIf { it.isNotBlank() }?.let {
                putExtra("teacher", it)
            }
            item.optString("originalText", "").takeIf { it.isNotBlank() }?.let {
                putExtra("original_text", it)
            }
            item.optString("analysisImagePath", "").takeIf { it.isNotBlank() }?.let {
                putExtra("analysis_image_path", it)
            }
            item.optString("planBlockId", "").takeIf { it.isNotBlank() }?.let {
                putExtra("plan_block_id", it)
            }
            item.optString("todoId", "").takeIf { it.isNotBlank() }?.let {
                putExtra("todo_id", it)
            }
        }

        val pi = PendingIntent.getBroadcast(
            this,
            ROLLING_ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (am.canScheduleExactAlarms()) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                } else {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                }
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            }
        } catch (e: Exception) {
            Log.e(TAG, "RollingAlarm: scheduleRollingAlarm error", e)
        }
    }

    private fun cancelRollingAlarm() {
        Log.d(TAG, "RollingAlarm: cancel rolling alarm")
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, ReminderAlarmReceiver::class.java).apply {
            action = ReminderAlarmReceiver.ACTION_FIRE
            setPackage(packageName)
        }

        val pi = PendingIntent.getBroadcast(
            this,
            ROLLING_ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )

        pi?.let {
            am.cancel(it)
            it.cancel()
        }
    }

    // ─────────────────────────────────────────────────────────────
    // 发出提醒通知
    // ─────────────────────────────────────────────────────────────

    private fun postReminderNotification(
        notifId: Int,
        title: String,
        text: String,
        analysisImagePath: String?,
        type: String?,
        todoType: String?,
        courseName: String?,
        room: String?,
        timeStr: String?,
        teacher: String?,
        originalText: String?,
        planBlockId: String?,
        todoId: String?
    ) {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (!analysisImagePath.isNullOrBlank()) {
                putExtra("analysis_image_path", analysisImagePath)
            }
            if (!originalText.isNullOrBlank()) {
                putExtra("original_analysis_text", originalText)
            }
            // 📅 规划块提醒 (notifId 33001-33999)：携带导航信息
            if (notifId in 33001..33999) {
                putExtra("open_plan_block", true)
                putExtra("plan_block_notif_id", notifId)
                if (!planBlockId.isNullOrBlank()) putExtra("plan_block_id", planBlockId)
                if (!todoId.isNullOrBlank()) putExtra("todo_id", todoId)
            }
        }
        val pi = PendingIntent.getActivity(
            this, notifId, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val display = buildLiveReminderDisplay(
            title = title,
            text = text,
            type = type,
            todoType = todoType,
            courseName = courseName,
            room = room,
            timeStr = timeStr,
            teacher = teacher,
            notifId = notifId
        )

        val builder = NotificationCompat.Builder(this, REMINDER_CHANNEL_ID)
            .setSmallIcon(display.iconResId)
            .setContentTitle(display.title)
            .setContentText(display.text)
            .setSubText(display.subText)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(false)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(display.color)
            .setColorized(false)
            .setContentIntent(pi)
            .setRequestPromotedOngoing(true)

        val extras = Bundle().apply {
            putBoolean("android.extra.requestPromotedOngoing", true)
        }

        if (Build.VERSION.SDK_INT >= 34 && display.shortText.isNotBlank()) {
            try {
                builder.setShortCriticalText(display.shortText)
            } catch (e: Exception) {
                Log.e(TAG, "setShortCriticalText error", e)
            }
        }

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
            builder.addAction(R.drawable.ic_notification, "查看图片", viewImagePi)
        }

        if (!originalText.isNullOrBlank()) {
            val viewTextIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("original_analysis_text", originalText)
            }
            val viewTextPi = PendingIntent.getActivity(
                this,
                notifId + 200000,
                viewTextIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            builder.addAction(R.drawable.ic_notification, "查看原文", viewTextPi)
        }

        try {
            if (HyperIslandNotification.isSupported(this)) {
                val hyperBuilder = HyperIslandNotification.Builder(this, display.islandBizTag, display.title)
                    .setSmallWindowTarget(MainActivity::class.java.name)

                val islandIcon = HyperPicture("island_icon", this, display.iconResId)
                hyperBuilder.addPicture(islandIcon)
                hyperBuilder.setBaseInfo(
                    title = display.title,
                    content = display.shortText.ifBlank { display.text },
                    pictureKey = "island_icon"
                )
                hyperBuilder.setIslandConfig(
                    priority = 2,
                    timeout = null,
                    dismissible = false,
                    needCloseAnimation = true
                )
                extras.putString("miui.focus.param", hyperBuilder.buildJsonParam())
                extras.putAll(hyperBuilder.buildResourceBundle())
            }
        } catch (e: Exception) {
            Log.e(TAG, "HyperIsland reminder setup failed", e)
        }

        builder.addExtras(extras)
        val notification = builder.build()

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try { nm.notify(notifId, notification) } catch (e: Exception) {
            Log.e(TAG, "postReminderNotification error", e)
        }
    }

    private data class ReminderDisplay(
        val title: String,
        val text: String,
        val subText: String,
        val shortText: String,
        val iconResId: Int,
        val color: Int,
        val islandBizTag: String
    )

    private fun buildLiveReminderDisplay(
        title: String,
        text: String,
        type: String?,
        todoType: String?,
        courseName: String?,
        room: String?,
        timeStr: String?,
        teacher: String?,
        notifId: Int
    ): ReminderDisplay {
        val normalizedType = when {
            !type.isNullOrBlank() -> type
            notifId in 31001..31999 -> "course"
            notifId in 32001..32999 -> "special_todo"
            notifId in 33001..33999 -> "plan_block"
            else -> "upcoming_todo"
        }

        return when (normalizedType) {
            "course" -> {
                val cleanTitle = courseName ?: title.removePrefix("📚").trim()
                val cleanRoom = room ?: text.substringAfter("·", "").trim()
                val courseText = listOfNotNull(
                    timeStr?.takeIf { it.isNotBlank() },
                    teacher?.takeIf { it.isNotBlank() },
                    cleanRoom.takeIf { it.isNotBlank() }
                ).joinToString(" | ").ifBlank { text }
                ReminderDisplay(
                    title = cleanTitle,
                    text = courseText,
                    subText = "🔔上课提醒",
                    shortText = cleanRoom.ifBlank { timeStr ?: "" },
                    iconResId = R.drawable.play_lesson,
                    color = 0xFF00ACC1.toInt(),
                    islandBizTag = COURSE_ISLAND_BIZ_TAG
                )
            }
            "special_todo" -> {
                val (icon, color, label) = when (todoType) {
                    "delivery" -> Triple(R.drawable.local_shipping, 0xFF4CAF50.toInt(), "取件")
                    "cafe" -> Triple(R.drawable.local_cafe, 0xFF795548.toInt(), "取餐")
                    "food" -> Triple(R.drawable.shopping_bag, 0xFFFF5722.toInt(), "取餐")
                    "restaurant" -> Triple(R.drawable.restaurant, 0xFF9C27B0.toInt(), "堂食")
                    else -> Triple(R.drawable.calendar_clock, 0xFFFF9800.toInt(), "待办")
                }
                ReminderDisplay(
                    title = title.replace(Regex("^\\S+\\s+"), ""),
                    text = text,
                    subText = label,
                    shortText = timeStr ?: text,
                    iconResId = icon,
                    color = color,
                    islandBizTag = SPECIAL_TODO_ISLAND_BIZ_TAG
                )
            }
            "plan_block" -> ReminderDisplay(
                title = title.removePrefix("📅 计划:").trim(),
                text = text,
                subText = "📅计划提醒",
                shortText = timeStr ?: text.substringBefore("·").trim(),
                iconResId = R.drawable.calendar_clock,
                color = 0xFF3F51B5.toInt(),
                islandBizTag = TODO_ISLAND_BIZ_TAG
            )
            else -> ReminderDisplay(
                title = title.removePrefix("⏰").trim(),
                text = text,
                subText = "🕒待办提醒",
                shortText = timeStr ?: text.substringAfter("·", text).trim(),
                iconResId = R.drawable.calendar_clock,
                color = 0xFFFF9800.toInt(),
                islandBizTag = TODO_ISLAND_BIZ_TAG
            )
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

        if (nm.getNotificationChannel(LIVE_CHANNEL_ID) == null) {
            val ch = NotificationChannel(
                LIVE_CHANNEL_ID,
                "Live Activities",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "课程和待办提醒的实时活动通知"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(ch)
        }

        if (nm.getNotificationChannel(REMINDER_CHANNEL_ID) == null) {
            val ch = NotificationChannel(
                REMINDER_CHANNEL_ID,
                "事件提醒",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "课程/待办/番茄钟开始与结束的一次性提醒"
                enableVibration(true)
                setShowBadge(false)
            }
            nm.createNotificationChannel(ch)
        }
    }
}

