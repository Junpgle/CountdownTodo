package com.math_quiz.junpgle.com.math_quiz_app

import android.app.*
import android.app.usage.UsageStatsManager
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import androidx.core.graphics.drawable.IconCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*
import org.json.JSONArray as KJSONArray

// 导入 HyperIsland Kit 的核心类
import io.github.d4viddf.hyperisland_kit.HyperAction
import io.github.d4viddf.hyperisland_kit.HyperIslandNotification
import io.github.d4viddf.hyperisland_kit.HyperPicture

// 导入 Shizuku 核心类
import rikka.shizuku.Shizuku

class MainActivity: FlutterActivity(), Shizuku.OnRequestPermissionResultListener, Shizuku.OnBinderReceivedListener, Shizuku.OnBinderDeadListener {
    private val CHANNEL = "com.math_quiz.junpgle.com.math_quiz_app/notifications"
    private val SCREEN_TIME_CHANNEL = "com.math_quiz_app/screen_time"
    private val NOTIFICATION_CHANNEL_ID = "live_updates_official_v2"
    // 🍅 番茄钟专属低功耗频道：IMPORTANCE_LOW 不唤醒屏幕、不振动
    private val POMODORO_CHANNEL_ID = "pomodoro_timer_low"
    // 🔔 普通提醒频道：IMPORTANCE_DEFAULT，有声音/震动，可同步手环，仅上岛时伴随触发一次
    private val ALERT_CHANNEL_ID = "event_alert_v1"
    private val NOTIFICATION_ID = 12345          // 主通知 ID（待办/测验）
    private val POMODORO_NOTIFICATION_ID = 12346 // 🍅 番茄钟独立通知 ID
    private val COURSE_NOTIFICATION_ID   = 12347 // 📚 课程提醒独立通知 ID
    private val ALERT_COURSE_ID   = 12348 // 🔔 课程普通提醒
    private val ALERT_TODO_ID     = 12349 // 🔔 待办普通提醒
    private val ALERT_POMO_START_ID = 12350 // 🔔 番茄开始普通提醒
    private val ALERT_POMO_END_ID   = 12351 // 🔔 番茄结束普通提醒
    private val TODO_ISLAND_BIZ_TAG     = "math_quiz_todo"     // 待办独立岛 bizTag
    private val COURSE_ISLAND_BIZ_TAG   = "math_quiz_course"   // 📚 课程独立岛 bizTag
    private val POMODORO_ISLAND_BIZ_TAG = "math_quiz_pomodoro" // 🍅 番茄钟独立岛 bizTag
    private val TAG = "MathQuizApp"

    // 全局保存 MethodChannel 实例，以便在广播中调用 Flutter
    private var methodChannel: MethodChannel? = null

    // 专门接收"点击完成"按钮的广播接收器
    private val todoActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            Log.d(TAG, "✅ Received MARK_DONE intent: $intent")
            if (intent?.action == "com.math_quiz.MARK_DONE") {
                methodChannel?.invokeMethod("markCurrentTodoDone", null)
                Log.d(TAG, "✅ Invoked markCurrentTodoDone to Flutter")
            }
        }
    }

    // 专门接收番茄钟按钮事件的广播接收器
    private val pomodoroActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                "com.math_quiz.POMODORO_FINISH_EARLY" -> {
                    Log.d(TAG, "🍅 Received POMODORO_FINISH_EARLY intent")
                    methodChannel?.invokeMethod("pomodoroFinishEarly", null)
                    Log.d(TAG, "🍅 Invoked pomodoroFinishEarly to Flutter")
                }
                "com.math_quiz.POMODORO_ABANDON" -> {
                    Log.d(TAG, "🍅 Received POMODORO_ABANDON intent")
                    methodChannel?.invokeMethod("pomodoroAbandon", null)
                    Log.d(TAG, "🍅 Invoked pomodoroAbandon to Flutter")
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        HomeWidgetPlugin.getData(this)

        // 注册 Shizuku 权限请求与生命周期监听器
        Shizuku.addRequestPermissionResultListener(this)
        Shizuku.addBinderReceivedListener(this)
        Shizuku.addBinderDeadListener(this)

        // 动态注册广播接收器
        val filter = IntentFilter("com.math_quiz.MARK_DONE")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(todoActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(todoActionReceiver, filter)
        }

        // 注册番茄钟按钮接收器
        val pomodoroFilter = IntentFilter().apply {
            addAction("com.math_quiz.POMODORO_FINISH_EARLY")
            addAction("com.math_quiz.POMODORO_ABANDON")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pomodoroActionReceiver, pomodoroFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(pomodoroActionReceiver, pomodoroFilter)
        }

        Log.d(TAG, "🚀 Broadcast receiver registered: ${todoActionReceiver::class.java.simpleName}, ${pomodoroActionReceiver::class.java.simpleName}")
    }

    override fun onDestroy() {
        super.onDestroy()
        // 移除监听器，防止内存泄漏
        Shizuku.removeRequestPermissionResultListener(this)
        Shizuku.removeBinderReceivedListener(this)
        Shizuku.removeBinderDeadListener(this)

        // 注销广播接收器并清空 channel，防内存泄漏
        unregisterReceiver(todoActionReceiver)
        unregisterReceiver(pomodoroActionReceiver)
        methodChannel = null
    }

    // Shizuku 服务成功连接的回调
    override fun onBinderReceived() {
        Log.i(TAG, "Shizuku Binder Received: Connected successfully!")
    }

    // Shizuku 服务断开的回调
    override fun onBinderDead() {
        Log.w(TAG, "Shizuku Binder Dead: Connection lost!")
    }

    // 接收 Shizuku 授权弹窗的结果
    override fun onRequestPermissionResult(requestCode: Int, grantResult: Int) {
        if (requestCode == 1001) {
            if (grantResult == PackageManager.PERMISSION_GRANTED) {
                Log.i(TAG, "Shizuku permission granted!")
            } else {
                Log.w(TAG, "Shizuku permission denied by user!")
            }
        }
    }

    // 🚀 新增：一键将小部件固定到桌面的方法 (Android 8.0+)
    private fun addWidgetToHome(): Boolean {
        val appWidgetManager = AppWidgetManager.getInstance(this)
        val myWidget = ComponentName(this, TodoWidgetProvider::class.java)

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (appWidgetManager.isRequestPinAppWidgetSupported) {
                // 创建成功添加后的回调 PendingIntent
                val successCallback = PendingIntent.getActivity(
                    this,
                    0,
                    Intent(this, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                appWidgetManager.requestPinAppWidget(myWidget, null, successCallback)
                true
            } else {
                false // 桌面启动器不支持
            }
        } else {
            false // Android 版本低于 8.0
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

        // 赋值给全局变量
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "showOngoingNotification" -> {
                    val args = call.arguments as? Map<String, Any>
                    if (args != null) {
                        val type = args["type"] as? String
                        when (type) {
                            "quiz" -> updateQuizNotification(args)
                            "course" -> updateCourseNotification(args)
                            "upcoming_todo" -> updateUpcomingTodoNotification(args)
                            "pomodoro" -> updatePomodoroNotification(args)
                            "pomodoro_end" -> sendPomodoroEndAlert(args)
                            else -> updateTodoNotification(args)
                        }
                        result.success(null)
                    } else result.error("INVALID_ARGS", "Arguments were null", null)
                }

                "cancelNotification" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancel(NOTIFICATION_ID)
                    nm.cancel(COURSE_NOTIFICATION_ID)          // 📚 清除课程独立通知
                    nm.cancel(POMODORO_NOTIFICATION_ID)        // 🍅 清除番茄钟独立通知
                    result.success(null)
                }

                // 🚀 响应 Flutter 的添加小部件请求
                "requestPinWidget" -> {
                    val success = addWidgetToHome()
                    result.success(success)
                }

                // 让 Flutter 端可以请求 Shizuku 授权
                "requestShizukuPermission" -> {
                    if (Shizuku.pingBinder()) {
                        if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                            Shizuku.requestPermission(1001)
                            result.success(true) // 已发起请求
                        } else {
                            result.success(true) // 已经有权限了
                        }
                    } else {
                        Log.e(TAG, "requestShizukuPermission: pingBinder returned false.")
                        result.success(false) // Shizuku 服务未运行或包可见性限制
                    }
                }

                // 处理 Flutter 的检测请求
                "checkIslandSupport" -> {
                    try {
                        val isSupported = HyperIslandNotification.isSupported(this@MainActivity)
                        result.success(isSupported)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                // 跳转到忽略电池优化设置页
                "openBatteryOptimizationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                // 检查 Android 16 实时通知权限
                "checkLiveUpdatesPermission" -> {
                    if (Build.VERSION.SDK_INT >= 36) {
                        try {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            val canPost = nm.javaClass.getMethod("canPostPromotedNotifications").invoke(nm) as Boolean
                            result.success(canPost)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(true) // 旧版本默认 true
                    }
                }

                // 跳转 Android 16 实时通知设置页
                "openLiveUpdatesSettings" -> {
                    if (Build.VERSION.SDK_INT >= 36) {
                        try {
                            val intent = Intent("android.settings.APP_NOTIFICATION_PROMOTION_SETTINGS").apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }

                // ── 保活：调度提醒 Alarm ──────────────────────────────────
                /**
                 * Flutter 端调用示例：
                 * await _channel.invokeMethod('scheduleReminders', {
                 * 'remindersJson': '[{"triggerAtMs":1234567890000,"title":"上课啦","text":"数学","notifId":30001}]'
                 * });
                 * 此方法将 JSON 写入 SharedPreferences，然后启动 ReminderService 注册 Alarm。
                 */
                "scheduleReminders" -> {
                    val args = call.arguments as? Map<String, Any>
                    val newJson = args?.get("remindersJson") as? String ?: "[]"
                    val prefs = getSharedPreferences(ReminderService.PREFS_NAME, MODE_PRIVATE)

                    // ── Upsert：按 notifId 合并，不覆盖其他提醒 ──────────────
                    val existing = KJSONArray(
                        prefs.getString(ReminderService.KEY_REMINDERS, "[]") ?: "[]"
                    )
                    val incoming = KJSONArray(newJson)

                    val incomingIds = mutableSetOf<Int>()
                    for (i in 0 until incoming.length()) {
                        incomingIds.add(incoming.getJSONObject(i).optInt("notifId", -1))
                    }
                    val merged = KJSONArray()
                    for (i in 0 until existing.length()) {
                        val obj = existing.getJSONObject(i)
                        if (!incomingIds.contains(obj.optInt("notifId", -1))) {
                            merged.put(obj)
                        }
                    }
                    for (i in 0 until incoming.length()) {
                        merged.put(incoming.getJSONObject(i))
                    }

                    prefs.edit().putString(ReminderService.KEY_REMINDERS, merged.toString()).apply()
                    startForegroundService(
                        Intent(this, ReminderService::class.java).apply {
                            action = ReminderService.ACTION_RESCHEDULE
                        }
                    )
                    result.success(true)
                }

                "cancelReminder" -> {
                    val args = call.arguments as? Map<String, Any>
                    val notifId = (args?.get("notifId") as? Number)?.toInt()
                        ?: return@setMethodCallHandler
                    val prefs = getSharedPreferences(ReminderService.PREFS_NAME, MODE_PRIVATE)
                    val existing = KJSONArray(
                        prefs.getString(ReminderService.KEY_REMINDERS, "[]") ?: "[]"
                    )
                    val filtered = KJSONArray()
                    for (i in 0 until existing.length()) {
                        val obj = existing.getJSONObject(i)
                        if (obj.optInt("notifId", -1) != notifId) filtered.put(obj)
                    }
                    prefs.edit().putString(ReminderService.KEY_REMINDERS, filtered.toString()).apply()

                    val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val intent = Intent(this, ReminderAlarmReceiver::class.java).apply {
                        action = ReminderAlarmReceiver.ACTION_FIRE
                    }
                    val pi = PendingIntent.getBroadcast(
                        this, notifId, intent,
                        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                    )
                    pi?.let { am.cancel(it) }
                    result.success(true)
                }

                "checkExactAlarmPermission" -> {
                    val canSchedule = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        (getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()
                    } else true
                    result.success(canSchedule)
                }

                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                data = android.net.Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(true)
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_TIME_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkUsagePermission" -> result.success(hasUsageStatsPermission())

                "openUsageSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }

                "getScreenTimeData" -> {
                    Thread {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                        try {
                            val data = getSystemAggregatedUsageStats()
                            runOnUiThread {
                                result.success(data)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("ERROR", "Failed: ${e.message}", null)
                            }
                        }
                    }.start()
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun getSystemAggregatedUsageStats(): Map<String, Any> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)

        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()

        // 🚀 记录本次统计对应的日期 (yyyy-MM-dd)
        val dateStr = android.text.format.DateFormat.format("yyyy-MM-dd", calendar).toString()

        val isTablet =
            (resources.configuration.screenLayout and Configuration.SCREENLAYOUT_SIZE_MASK) >= Configuration.SCREENLAYOUT_SIZE_LARGE
        val deviceType = if (isTablet) "Android-Tablet" else "Android-Phone"

        val statsMap = usageStatsManager.queryAndAggregateUsageStats(startTime, endTime)
        val pm = packageManager
        val appsList = mutableListOf<Map<String, Any>>()

        for ((pkgName, usageStats) in statsMap) {
            val totalTimeMs = usageStats.totalTimeInForeground

            if (totalTimeMs > 60000) {
                if (pkgName == "android" || pkgName == "com.android.systemui" || pkgName.contains("launcher")) continue

                val label = try {
                    val info = pm.getApplicationInfo(pkgName, 0)
                    pm.getApplicationLabel(info).toString()
                } catch (e: Exception) {
                    pkgName
                }

                if (label == pkgName && pkgName.startsWith("com.android.")) continue

                appsList.add(
                    mapOf(
                        "app_name" to label,
                        "duration" to (totalTimeMs / 1000).toInt(),
                        "device_type" to deviceType
                    )
                )
            }
        }

        return mapOf(
            "date" to dateStr,
            "apps" to appsList
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // 主频道：Live Activities（课程/待办 高优先级）
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Live Activities",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setSound(null, null)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(channel)

            // 🍅 番茄钟专属频道：低优先级，不唤醒屏幕，不振动，省电
            val pomodoroChannel = NotificationChannel(
                POMODORO_CHANNEL_ID,
                "番茄钟计时",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "专注/休息倒计时常驻通知"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(pomodoroChannel)

            // 🔔 普通提醒频道：上岛时伴随触发一次，可同步手环，每事件只响一次
            val alertChannel = NotificationChannel(
                ALERT_CHANNEL_ID,
                "事件提醒",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "课程/待办/番茄钟开始与结束的一次性提醒（可同步手环）"
                enableVibration(true)
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(alertChannel)
        }
    }

    private fun updateCourseNotification(args: Map<String, Any>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val courseName = args["courseName"] as? String ?: "未知课程"
        val room = args["room"] as? String ?: "未知教室"
        val timeStr = args["timeStr"] as? String ?: ""
        val teacher = args["teacher"] as? String ?: ""

        // 小岛左侧标题：课程名称；小岛右侧内容/胶囊短文本：教室
        val title = courseName
        val text = "$timeStr | $teacher | $room"
        val subText = "🔔上课提醒"
        val color = 0xFF00ACC1.toInt()

        buildAndNotify(
            title = title,
            text = text,
            subText = subText,
            progress = 0,
            isOngoing = true,
            color = color,
            currentStep = 0,
            totalSteps = 0,
            isTodo = false,
            shortText = room,
            iconResId = R.drawable.play_lesson,
            notificationId = COURSE_NOTIFICATION_ID,
            islandBizTag   = COURSE_ISLAND_BIZ_TAG
        )
        // 🔔 上岛同时触发一次性普通提醒（可同步手环），相同课程+时间段不重复
        sendAlertIfNew(
            alertKey = "course_${courseName}_${timeStr}",
            title = "📚 $courseName",
            text = "$timeStr · $room",
            alertNotificationId = ALERT_COURSE_ID,
            iconResId = R.drawable.play_lesson
        )
    }

    private fun updateQuizNotification(args: Map<String, Any>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val currentIndex = (args["currentIndex"] as? Number)?.toInt() ?: 0
        val totalCount = (args["totalCount"] as? Number)?.toInt() ?: 10
        val questionText = args["questionText"] as? String ?: "Ready..."
        val isOver = args["isOver"] as? Boolean ?: false
        val score = (args["score"] as? Number)?.toInt() ?: 0
        val progress =
            if (isOver) 100 else if (totalCount > 0) ((currentIndex) * 100) / totalCount else 0

        val title: String
        val text: String
        val subText: String
        val color: Int

        if (isOver) {
            title = "Quiz Finished! \uD83C\uDFC6"
            text = "Final Score: $score / ${totalCount * 10}"
            subText = "Completed"
            color = 0xFFF4B400.toInt()
        } else {
            title = "Question ${currentIndex + 1} of $totalCount"
            text = questionText
            subText = "Math Quiz"
            color = 0xFF673AB7.toInt()
        }

        buildAndNotify(
            title = title,
            text = text,
            subText = subText,
            progress = progress,
            isOngoing = !isOver,
            color = color,
            currentStep = if (isOver) totalCount else currentIndex + 1,
            totalSteps = totalCount,
            isTodo = false
        )
    }

    // 🍅 番茄钟实时通知
    private fun updatePomodoroNotification(args: Map<String, Any>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val phase        = args["phase"]         as? String ?: "focusing"
        val countdown    = args["countdown"]     as? String ?: "25:00"
        val todoTitle    = (args["todoTitle"]    as? String)?.trim() ?: ""
        val currentCycle = (args["currentCycle"] as? Number)?.toInt() ?: 1
        val totalCycles  = (args["totalCycles"]  as? Number)?.toInt() ?: 4
        @Suppress("UNCHECKED_CAST")
        val tagNames     = (args["tagNames"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
        // alertKey 非空时说明这是一个"开始"事件，触发一次性普通提醒
        val alertKey     = (args["alertKey"] as? String)?.trim() ?: ""

        val isFocusing = phase == "focusing"

        val phaseLabel = if (isFocusing) "🍅 专注中" else "☕ 休息中"
        val title = "$phaseLabel  $countdown"

        val taskLine = when {
            todoTitle.isNotEmpty() -> todoTitle
            isFocusing             -> "自由专注"
            else                   -> "稍作休息，准备下一轮"
        }
        val tagsLine = if (tagNames.isNotEmpty()) tagNames.joinToString("  ") { "🏷 $it" } else ""
        val text = if (tagsLine.isNotEmpty()) "$taskLine\n$tagsLine" else taskLine

        val subText = "第 $currentCycle/$totalCycles 轮"
        val color = if (isFocusing) 0xFFF44336.toInt() else 0xFF4CAF50.toInt()
        val shortText = countdown
        val iconResId = if (isFocusing) R.drawable.hourglass else R.drawable.hourglass_check

        buildAndNotify(
            title          = title,
            text           = text,
            subText        = subText,
            progress       = 0,
            isOngoing      = true,
            color          = color,
            currentStep    = 0,
            totalSteps     = 0,
            isTodo         = false,
            shortText      = shortText,
            iconResId      = iconResId,
            channelId      = POMODORO_CHANNEL_ID,
            notificationId = POMODORO_NOTIFICATION_ID,
            islandBizTag   = POMODORO_ISLAND_BIZ_TAG
        )

        // 🔔 只有携带 alertKey 时才触发一次性普通提醒（开始事件）
        if (alertKey.isNotEmpty()) {
            val alertTitle = if (isFocusing) "🍅 专注开始" else "☕ 休息开始"
            val alertText  = if (taskLine.isNotEmpty()) taskLine else "${totalCycles}轮番茄钟"
            sendAlertIfNew(
                alertKey = alertKey,
                title = alertTitle,
                text = alertText,
                alertNotificationId = ALERT_POMO_START_ID,
                iconResId = iconResId
            )
        }
    }

    // 🍅 番茄钟结束一次性提醒（由 Flutter 在专注/休息结束时单独触发）
    private fun sendPomodoroEndAlert(args: Map<String, Any>) {
        val alertKey  = (args["alertKey"]  as? String)?.trim() ?: return
        val todoTitle = (args["todoTitle"] as? String)?.trim() ?: ""
        val isBreak   = args["isBreak"] as? Boolean ?: false
        val alertTitle = if (isBreak) "☕ 休息结束，准备下一轮" else "🍅 专注完成！"
        val alertText  = if (todoTitle.isNotEmpty()) todoTitle else "干得不错，继续保持！"
        sendAlertIfNew(
            alertKey = alertKey,
            title = alertTitle,
            text = alertText,
            alertNotificationId = ALERT_POMO_END_ID,
            iconResId = R.drawable.hourglass_check
        )
    }

    // 🚀 新增：处理即将开始的具体时间待办
    private fun updateUpcomingTodoNotification(args: Map<String, Any>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val todoTitle = args["todoTitle"] as? String ?: "待办事项"
        val todoRemark = (args["todoRemark"] as? String)?.trim() ?: ""
        val timeStr = args["timeStr"] as? String ?: ""

        // 主标题 = 待办内容；正文 = 备注（有则显示）否则显示时间段；subText = 🕒即将开始 + 时间
        val title = todoTitle
        val text = if (todoRemark.isNotEmpty()) todoRemark else "时间: $timeStr"
        val subText = "🕒即将开始 · $timeStr"
        val color = 0xFFFF9800.toInt() // 橙色警示

        buildAndNotify(
            title = title,
            text = text,
            subText = subText,
            progress = 0,
            isOngoing = true,
            color = color,
            currentStep = 0,
            totalSteps = 0,
            isTodo = true,
            shortText = timeStr,
            iconResId = R.drawable.calendar_clock
        )
        // 🔔 上岛同时触发一次性普通提醒
        sendAlertIfNew(
            alertKey = "todo_${todoTitle}_${timeStr}",
            title = "🕒 $todoTitle",
            text = if (todoRemark.isNotEmpty()) todoRemark else "即将开始 · $timeStr",
            alertNotificationId = ALERT_TODO_ID,
            iconResId = R.drawable.calendar_clock
        )
    }

    // 负责"全天"待办的汇总显示
    private fun updateTodoNotification(args: Map<String, Any>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val totalCount = (args["totalCount"] as? Number)?.toInt() ?: 0
        val completedCount = (args["completedCount"] as? Number)?.toInt() ?: 0
        val pendingTitlesRaw = args["pendingTitles"] as? List<*>
        val pendingTitles = pendingTitlesRaw?.filterIsInstance<String>() ?: emptyList()
        val pendingRemarksRaw = args["pendingRemarks"] as? List<*>
        val pendingRemarks = pendingRemarksRaw?.filterIsInstance<String>() ?: emptyList()

        // 如果连待办都没有了，直接取消（这和 Flutter 端的逻辑对应）
        if (totalCount == 0) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(NOTIFICATION_ID)
            return
        }

        val isAllDone = completedCount == totalCount && totalCount > 0
        val progress = if (totalCount > 0) (completedCount * 100) / totalCount else 0

        val title: String
        val text: String
        val subText = "$completedCount/$totalCount Done"
        val color: Int

        if (isAllDone) {
            title = "All Day Tasks Completed! \uD83C\uDF89"
            text = "Great job clearing your list."
            color = 0xFF0F9D58.toInt()
        } else {
            title = if (pendingTitles.isNotEmpty()) "全天: ${pendingTitles[0]}" else "Keep Going!"
            // 第一条未完成待办有备注时，用备注作为副标题；否则显示后续待办或 "Almost there!"
            val firstRemark = pendingRemarks.getOrNull(0)?.trim() ?: ""
            text = when {
                firstRemark.isNotEmpty() -> firstRemark
                pendingTitles.size > 1   -> "Next: ${pendingTitles.drop(1).joinToString(", ")}"
                else                     -> "Almost there!"
            }
            color = 0xFF4285F4.toInt()
        }

        buildAndNotify(
            title = title,
            text = text,
            subText = subText,
            progress = progress,
            isOngoing = !isAllDone,
            color = color,
            currentStep = completedCount,
            totalSteps = totalCount,
            isTodo = true
        )
    }

    /**
     * 🔔 发送一次性普通提醒（可同步手环）。
     * 用 SharedPreferences 记录已提醒的 alertKey，相同 key 不重复发送。
     * alertKey 应体现事件的唯一性（如 "course_<名称>_<时间>" / "pomo_start_<endMs>"）。
     */
    private fun sendAlertIfNew(
        alertKey: String,
        title: String,
        text: String,
        alertNotificationId: Int,
        iconResId: Int = R.drawable.ic_notification
    ) {
        val prefs = getSharedPreferences("alert_keys", MODE_PRIVATE)
        val lastKey = prefs.getString("last_alerted_key_$alertNotificationId", "")
        if (lastKey == alertKey) return // 已提醒过，跳过

        prefs.edit().putString("last_alerted_key_$alertNotificationId", alertKey).apply()

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, alertNotificationId, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(iconResId)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .build()
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(alertNotificationId, notification)
        } catch (e: Exception) {
            Log.e(TAG, "sendAlertIfNew error", e)
        }
    }

    private fun buildAndNotify(
        title: String,
        text: String,
        subText: String,
        progress: Int,
        isOngoing: Boolean,
        color: Int,
        currentStep: Int,
        totalSteps: Int,
        isTodo: Boolean = false,
        shortText: String? = null,
        iconResId: Int = R.drawable.ic_notification,
        channelId: String = NOTIFICATION_CHANNEL_ID,
        notificationId: Int = NOTIFICATION_ID,
        islandBizTag: String = TODO_ISLAND_BIZ_TAG
    ) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val intent = Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP }
        val pendingIntent: PendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // ==========================================
        // 🚀 构建基础的 NotificationCompat.Builder
        // ==========================================
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(iconResId)
            .setLargeIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
            .setContentTitle(title)
            .setContentText(text)
            .setSubText(subText)
            .setOngoing(isOngoing)
            .setOnlyAlertOnce(true)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(color)
            .setColorized(false)
            .setContentIntent(pendingIntent)
            .setRequestPromotedOngoing(true)

        // 🚨 显式要求系统提升为“推荐的持续通知”(Live Updates)
        val extras = Bundle()
        extras.putBoolean("android.extra.requestPromotedOngoing", true)

        // ==========================================
        // 🚀 构建完全对齐官方的 ProgressStyle / Short Text
        // ==========================================
        var appliedProgressStyle = false

        if (Build.VERSION.SDK_INT >= 34) {
            try {
                // 1. 设置极简短文本 (用于胶囊/锁屏)，优先使用传入的 shortText (例如教室信息)
                val textToUse = shortText ?: if (totalSteps > 0) "$currentStep/$totalSteps" else null
                if (textToUse != null) {
                    builder.setShortCriticalText(textToUse)
                }

                if (totalSteps > 0) {
                    // 2. 颜色配置
                    val pointColor = color
                    val segmentColor = android.graphics.Color.argb(76,
                        android.graphics.Color.red(color),
                        android.graphics.Color.green(color),
                        android.graphics.Color.blue(color)
                    )

                    val progressStyle = NotificationCompat.ProgressStyle()

                    // 3. 构建分段 (Segments)
                    val segmentsList = mutableListOf<NotificationCompat.ProgressStyle.Segment>()
                    val segmentWeight = 100 / totalSteps
                    for (i in 1..totalSteps) {
                        val w = if (i == totalSteps) 100 - (segmentWeight * (totalSteps - 1)) else segmentWeight
                        segmentsList.add(NotificationCompat.ProgressStyle.Segment(w).setColor(segmentColor))
                    }
                    progressStyle.setProgressSegments(segmentsList)

                    // 4. 构建节点 (Points)
                    val pointsList = mutableListOf<NotificationCompat.ProgressStyle.Point>()
                    for (i in 1..totalSteps) {
                        if (i <= currentStep && isOngoing) {
                            val p = (i * 100) / totalSteps
                            pointsList.add(NotificationCompat.ProgressStyle.Point(p).setColor(pointColor))
                        } else if (!isOngoing) {
                            val p = (i * 100) / totalSteps
                            pointsList.add(NotificationCompat.ProgressStyle.Point(p).setColor(pointColor))
                        }
                    }
                    if (pointsList.isNotEmpty()) {
                        progressStyle.setProgressPoints(pointsList)
                    }

                    // 5. 设置 Tracker 图标 - 强行给图标上色
                    val trackerIconRes = if (isOngoing) R.drawable.ic_done else 0 // 或者其他默认图标
                    if (trackerIconRes != 0) {
                        val trackerIcon = IconCompat.createWithResource(this, trackerIconRes)
                        trackerIcon.setTint(color)
                        progressStyle.setProgressTrackerIcon(trackerIcon)
                    }

                    // 6. 将样式应用到 Builder
                    val currentPercent = if (totalSteps > 0) (currentStep * 100) / totalSteps else 0
                    builder.setStyle(progressStyle.setProgress(currentPercent))

                    // 标记成功应用，不执行后方的基础兜底
                    appliedProgressStyle = true
                }
            } catch (e: Exception) {
                Log.e(TAG, "Apply ProgressStyle Failed", e)
            }
        }

        // ❌ 兜底进度条渲染
        if (!appliedProgressStyle && totalSteps > 0) {
            val fallbackProgress = if (totalSteps > 0) (currentStep * 100) / totalSteps else 0
            builder.setProgress(100, fallbackProgress, false)
        }

        // ==========================================
        //  为未完成的待办事项准备「完成」广播 Intent
        // ==========================================
        var actionPendingIntent: PendingIntent? = null
        if (isTodo && isOngoing) {
            val actionIntent = Intent("com.math_quiz.MARK_DONE").apply {
                setPackage(packageName)
            }
            actionPendingIntent = PendingIntent.getBroadcast(
                this, 100, actionIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )

            val nativeAction = NotificationCompat.Action.Builder(
                IconCompat.createWithResource(this, R.drawable.ic_done),
                "完成",
                actionPendingIntent
            ).build()
            builder.addAction(nativeAction)
        }

        // ==========================================
        //  为番茄钟添加「提前完成」和「放弃专注」按钮
        // ==========================================
        var pomodoroFinishPendingIntent: PendingIntent? = null
        var pomodoroAbandonPendingIntent: PendingIntent? = null
        
        if (channelId == POMODORO_CHANNEL_ID && isOngoing) {
            // 提前完成
            val finishIntent = Intent("com.math_quiz.POMODORO_FINISH_EARLY").apply {
                setPackage(packageName)
            }
            pomodoroFinishPendingIntent = PendingIntent.getBroadcast(
                this, 101, finishIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            val finishAction = NotificationCompat.Action.Builder(
                IconCompat.createWithResource(this, R.drawable.ic_done),
                "提前完成",
                pomodoroFinishPendingIntent
            ).build()
            builder.addAction(finishAction)

            // 放弃专注
            val abandonIntent = Intent("com.math_quiz.POMODORO_ABANDON").apply {
                setPackage(packageName)
            }
            pomodoroAbandonPendingIntent = PendingIntent.getBroadcast(
                this, 102, abandonIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            val abandonAction = NotificationCompat.Action.Builder(
                IconCompat.createWithResource(this, R.drawable.ic_cancel),
                "放弃专注",
                pomodoroAbandonPendingIntent
            ).build()
            builder.addAction(abandonAction)
        }

        // ==========================================
        //  小米 HyperOS 超级岛 (Dynamic Island) 适配
        // ==========================================
        try {
            if (HyperIslandNotification.isSupported(this)) {
                val hyperBuilder = HyperIslandNotification.Builder(this, islandBizTag, title)
                    .setSmallWindowTarget(MainActivity::class.java.name)

                val islandIcon = HyperPicture("island_icon", this, iconResId)
                hyperBuilder.addPicture(islandIcon)

                hyperBuilder.setBaseInfo(
                    title = title,
                    content = shortText ?: text, // 优先显示短文本（比如教室信息或时间）
                    pictureKey = "island_icon"
                )

                hyperBuilder.setIslandConfig(
                    priority = 2,
                    timeout = null,
                    dismissible = !isOngoing,
                    needCloseAnimation = true
                )

                if (totalSteps > 0 && isOngoing) {
                    val hexColor = String.format("#%06X", 0xFFFFFF and color)
                    hyperBuilder.setStepProgress(currentStep, totalSteps, hexColor)
                }

                if (actionPendingIntent != null) {
                    val doneAction = HyperAction(
                        "btn_done",
                        "完成",
                        actionPendingIntent,
                        1
                    )
                    hyperBuilder.addAction(doneAction)
                }

                if (pomodoroFinishPendingIntent != null) {
                    val finishAction = HyperAction(
                        "btn_finish",
                        "提前完成",
                        pomodoroFinishPendingIntent,
                        1
                    )
                    hyperBuilder.addAction(finishAction)
                }
                
                if (pomodoroAbandonPendingIntent != null) {
                    val abandonAction = HyperAction(
                        "btn_abandon",
                        "放弃专注",
                        pomodoroAbandonPendingIntent,
                        2
                    )
                    hyperBuilder.addAction(abandonAction)
                }

                extras.putString("miui.focus.param", hyperBuilder.buildJsonParam())
                extras.putAll(hyperBuilder.buildResourceBundle())
            }
        } catch (e: Exception) {
            Log.e(TAG, "HyperIsland Setup Failed", e)
        }

        // 统一添加 Extras
        builder.addExtras(extras)

        // ==========================================
        // 发送通知与权限检查
        // ==========================================
        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= 36) {
            try {
                val canPost = notificationManager.javaClass.getMethod("canPostPromotedNotifications").invoke(notificationManager) as? Boolean ?: false
                val hasPromo = notification.javaClass.getMethod("hasPromotableCharacteristics").invoke(notification) as? Boolean ?: false
                Log.w(TAG, "🚀 Live Updates Status -> Permitted by user: $canPost | Has Promotable Flags: $hasPromo")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to check Live Updates status via reflection", e)
            }
        }

        try {
            notificationManager.notify(notificationId, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Notify error", e)
        }
    }
}