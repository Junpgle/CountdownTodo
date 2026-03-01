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
            if (intent?.action == "com.math_quiz.MARK_DONE") {
                // 通知 Flutter 端去完成当前待办
                methodChannel?.invokeMethod("markCurrentTodoDone", null)
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

        val builder = Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setSubText(subText)
            .setProgress(100, progress, false)
            .setOngoing(isOngoing)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setShowWhen(false)
            .setColor(color)
            .setColorized(true)
            .setContentIntent(pendingIntent)

        val extras = Bundle()
        extras.putBoolean("android.extra.requestPromotedOngoing", true)

        // ==========================================
        //  为未完成的待办事项准备「完成」广播 Intent
        // ==========================================
        var actionPendingIntent: PendingIntent? = null
        if (isTodo && isOngoing) {
            val actionIntent = Intent("com.math_quiz.MARK_DONE").apply {
                setPackage(packageName) // 确保广播只发给自己的应用
            }
            actionPendingIntent = PendingIntent.getBroadcast(
                this, 100, actionIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // 核心修复：同步添加到原生 Android Notification 中，防止 HyperOS 吞掉下方按钮区
            val nativeAction = Notification.Action.Builder(
                Icon.createWithResource(this, R.mipmap.ic_launcher),
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

                val appIcon = HyperPicture("app_icon", this, R.mipmap.ic_launcher)
                hyperBuilder.addPicture(appIcon)

                hyperBuilder.setBaseInfo(
                    title = title,
                    content = text,
                    pictureKey = "app_icon"
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

                // 注入超级岛的 Action 配置
                if (actionPendingIntent != null) {
                    val doneAction = HyperAction(
                        "btn_done", // 唯一标识
                        "完成",     // 按钮文字
                        actionPendingIntent,
                        1           // actionIntentType: 1
                    )
                    hyperBuilder.addAction(doneAction)
                }

                extras.putString("miui.focus.param", hyperBuilder.buildJsonParam())
                extras.putAll(hyperBuilder.buildResourceBundle())
            }
        } catch (e: Exception) {
            Log.e(TAG, "HyperIsland Setup Failed", e)
        }

        builder.addExtras(extras)

        // ==========================================
        //  Shizuku 流程：拦截 xmsf -> 触发通知 -> 恢复网络
        // ==========================================
        Thread {
            var shizukuInteracted = false
            var targetUid = -1

            try {
                // 动态获取当前设备上 xmsf 的 UID
                targetUid = packageManager.getApplicationInfo("com.xiaomi.xmsf", 0).uid

                // 检查 Shizuku 服务状态与权限
                if (Shizuku.pingBinder() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                    // 1. 使用动态获取的 UID 禁用 xmsf 网络
                    val disableCmd = "cmd netpolicy add restrict-background-blacklist $targetUid"

                    // 使用反射调用 newProcess 绕过 Kotlin 返回值推断问题
                    val processMethod = Shizuku::class.java.getMethod(
                        "newProcess",
                        Array<String>::class.java,
                        Array<String>::class.java,
                        String::class.java
                    )
                    // 必须指定为 java.lang.Process 以防止和 android.os.Process 冲突
                    val p = processMethod.invoke(
                        null,
                        arrayOf("sh", "-c", disableCmd),
                        null,
                        null
                    ) as java.lang.Process
                    p.waitFor()

                    shizukuInteracted = true
                }
            } catch (e: Exception) {
                Log.e(TAG, "Shizuku disable network failed", e)
            }

            try {
                // 2. 发送通知
                notificationManager.notify(NOTIFICATION_ID, builder.build())
            } catch (e: Exception) {
                Log.e(TAG, "Notify error", e)
            }

            // 3. 恢复 xmsf 网络
            if (shizukuInteracted && targetUid != -1) {
                try {
                    Thread.sleep(1500)

                    val enableCmd = "cmd netpolicy remove restrict-background-blacklist $targetUid"

                    val processMethod = Shizuku::class.java.getMethod(
                        "newProcess",
                        Array<String>::class.java,
                        Array<String>::class.java,
                        String::class.java
                    )
                    val p = processMethod.invoke(
                        null,
                        arrayOf("sh", "-c", enableCmd),
                        null,
                        null
                    ) as java.lang.Process
                    p.waitFor()

                } catch (e: Exception) {
                    Log.e(TAG, "Shizuku enable network failed", e)
                }
            }
        }.start()
        // ==========================================
    }
}