package com.math_quiz.junpgle.com.math_quiz_app

import android.app.*
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*
import android.graphics.Color
import androidx.core.app.NotificationCompat
import androidx.core.graphics.drawable.IconCompat

// 导入 HyperIsland Kit 的核心类
import io.github.d4viddf.hyperisland_kit.HyperIslandNotification
import io.github.d4viddf.hyperisland_kit.HyperPicture

// 修正：HyperAction 和 HyperPicture 一样，在根目录下
import io.github.d4viddf.hyperisland_kit.HyperAction
import android.content.BroadcastReceiver
import android.content.IntentFilter

// 导入 Shizuku 核心类
import rikka.shizuku.Shizuku

class MainActivity: FlutterActivity(), Shizuku.OnRequestPermissionResultListener, Shizuku.OnBinderReceivedListener, Shizuku.OnBinderDeadListener {
    private val CHANNEL = "com.math_quiz.junpgle.com.math_quiz_app/notifications"
    private val SCREEN_TIME_CHANNEL = "com.math_quiz_app/screen_time"
    private val NOTIFICATION_CHANNEL_ID = "live_updates_official_v2"
    private val NOTIFICATION_ID = 12345
    private val TAG = "MathQuizApp"

    // 全局保存 MethodChannel 实例，以便在广播中调用 Flutter
    private var methodChannel: MethodChannel? = null

    // 专门接收“点击完成”按钮的广播接收器
    private val todoActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            Log.d(TAG, "✅ Received MARK_DONE intent: $intent")
            if (intent?.action == "com.math_quiz.MARK_DONE") {
                methodChannel?.invokeMethod("markCurrentTodoDone", null)
                Log.d(TAG, "✅ Invoked markCurrentTodoDone to Flutter")
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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

        Log.d(TAG, "🚀 Broadcast receiver registered: ${todoActionReceiver::class.java.simpleName}")
    }

    override fun onDestroy() {
        super.onDestroy()
        // 移除监听器，防止内存泄漏
        Shizuku.removeRequestPermissionResultListener(this)
        Shizuku.removeBinderReceivedListener(this)
        Shizuku.removeBinderDeadListener(this)

        // 注销广播接收器并清空 channel，防内存泄漏
        unregisterReceiver(todoActionReceiver)
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
                        if (type == "quiz") updateQuizNotification(args) else updateTodoNotification(
                            args
                        )
                        result.success(null)
                    } else result.error("INVALID_ARGS", "Arguments were null", null)
                }

                "cancelNotification" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancel(NOTIFICATION_ID)
                    result.success(null)
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
                        // 直接调用 HyperIslandNotification 检查是否支持
                        val isSupported = HyperIslandNotification.isSupported(this@MainActivity)
                        result.success(isSupported)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                // === 新增：检查 Android 16 实时通知权限 ===
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
                // === 新增：跳转 Android 16 实时通知设置页 ===
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

    private fun getSystemAggregatedUsageStats(): List<Map<String, Any>> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)

        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()

        val isTablet =
            (resources.configuration.screenLayout and Configuration.SCREENLAYOUT_SIZE_MASK) >= Configuration.SCREENLAYOUT_SIZE_LARGE
        val deviceType = if (isTablet) "Android-Tablet" else "Android-Phone"

        val statsMap = usageStatsManager.queryAndAggregateUsageStats(startTime, endTime)
        val pm = packageManager
        val usageStatsList = mutableListOf<Map<String, Any>>()

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

                usageStatsList.add(
                    mapOf(
                        "app_name" to label,
                        "duration" to (totalTimeMs / 1000).toInt(),
                        "device_type" to deviceType
                    )
                )
            }
        }

        return usageStatsList
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val name = "Live Activities"
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                name,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setSound(null, null)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
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

        val title: String;
        val text: String;
        val subText: String;
        val color: Int
        if (isOver) {
            title = "Quiz Finished! \uD83C\uDFC6"; text =
                "Final Score: $score / ${totalCount * 10}"; subText = "Completed"; color =
                0xFFF4B400.toInt()
        } else {
            title = "Question ${currentIndex + 1} of $totalCount"; text = questionText; subText =
                "Math Quiz"; color = 0xFF673AB7.toInt()
        }
        buildAndNotify(
            title,
            text,
            subText,
            progress,
            !isOver,
            color,
            if (isOver) totalCount else currentIndex + 1,
            totalCount
        )
    }

    private fun updateTodoNotification(args: Map<String, Any>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val totalCount = (args["totalCount"] as? Number)?.toInt() ?: 0
        val completedCount = (args["completedCount"] as? Number)?.toInt() ?: 0
        val pendingTitlesRaw = args["pendingTitles"] as? List<*>
        val pendingTitles = pendingTitlesRaw?.filterIsInstance<String>() ?: emptyList()
        val isAllDone = completedCount == totalCount && totalCount > 0
        val progress = if (totalCount > 0) (completedCount * 100) / totalCount else 0

        val title: String;
        val text: String;
        val subText = "$completedCount/$totalCount Done";
        val color: Int
        if (isAllDone) {
            title = "All Tasks Completed! \uD83C\uDF89"; text =
                "Great job clearing your list."; color = 0xFF0F9D58.toInt()
        } else {
            title =
                if (pendingTitles.isNotEmpty()) "Current: ${pendingTitles[0]}" else "Keep Going!"; text =
                if (pendingTitles.size > 1) "Next: ${
                    pendingTitles.drop(1).joinToString(", ")
                }" else "Almost there!"; color = 0xFF4285F4.toInt()
        }

        // 标记为待办任务，传入 isTodo = true
        buildAndNotify(
            title,
            text,
            subText,
            progress,
            !isAllDone,
            color,
            completedCount,
            totalCount,
            isTodo = true
        )
    }

    // 增加了 isTodo = false 默认参数
    private fun buildAndNotify(
        title: String,
        text: String,
        subText: String,
        progress: Int,
        isOngoing: Boolean,
        color: Int,
        currentStep: Int,
        totalSteps: Int,
        isTodo: Boolean = false
    ) {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val intent =
            Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP }
        val pendingIntent: PendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // ==========================================
        // 🚀 构建基础的 NotificationCompat.Builder
        // ==========================================
        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
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
            .setColorized(true)
            .setContentIntent(pendingIntent)

        // 🚨 显式要求系统提升为“推荐的持续通知”(Live Updates)
        val extras = Bundle()
        extras.putBoolean("android.extra.requestPromotedOngoing", true)

        // ==========================================
        // 🚀 构建完全对齐官方的 ProgressStyle
        // ==========================================
        var appliedProgressStyle = false

        if (Build.VERSION.SDK_INT >= 34 && totalSteps > 0) {
            try {
                // 1. 设置极简短文本 (用于胶囊/锁屏)
                builder.setShortCriticalText("$currentStep/$totalSteps")

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

                // 5. 设置 Tracker 图标 - 🚨核心修复：强行给图标上色，防止因为系统背景为白色导致隐形！
                val trackerIconRes = if (isOngoing) R.drawable.ic_notification else R.drawable.ic_done
                val trackerIcon = IconCompat.createWithResource(this, trackerIconRes)
                trackerIcon.setTint(color) // <--- 强行赋予主题色，绝对清晰可见！
                progressStyle.setProgressTrackerIcon(trackerIcon)

                // 6. 将样式应用到 Builder，并且 **只在这里** 调用 setProgress
                val currentPercent = if (totalSteps > 0) (currentStep * 100) / totalSteps else 0
                builder.setStyle(progressStyle.setProgress(currentPercent))

                // 标记成功应用，不执行后方的基础兜底
                appliedProgressStyle = true

            } catch (e: Exception) {
                Log.e(TAG, "Apply ProgressStyle Failed", e)
            }
        }

        // ❌ 兜底进度条渲染：不让它干扰 Live Updates
        if (!appliedProgressStyle) {
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

        // ==========================================
        //  小米 HyperOS 超级岛 (Dynamic Island) 适配
        // ==========================================
        try {
            if (HyperIslandNotification.isSupported(this)) {
                val hyperBuilder = HyperIslandNotification.Builder(this, "math_quiz_biz", title)
                    .setSmallWindowTarget(MainActivity::class.java.name)

                val islandIcon = HyperPicture("island_icon", this, R.drawable.ic_notification)
                hyperBuilder.addPicture(islandIcon)

                hyperBuilder.setBaseInfo(
                    title = title,
                    content = text,
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

        // 🚀 核心诊断：通过反射验证系统是否真正赋予了“实时更新”权限
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
            notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Notify error", e)
        }
    }
}