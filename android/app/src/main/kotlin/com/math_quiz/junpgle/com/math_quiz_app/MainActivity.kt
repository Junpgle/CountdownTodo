package com.math_quiz.junpgle.com.math_quiz_app

import android.app.*
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
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

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.math_quiz.junpgle.com.math_quiz_app/notifications"
    private val SCREEN_TIME_CHANNEL = "com.math_quiz_app/screen_time"
    private val NOTIFICATION_CHANNEL_ID = "live_updates_official_v2"
    private val NOTIFICATION_ID = 12345
    private val TAG = "MathQuizApp"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

        // 通知通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showOngoingNotification" -> {
                    val args = call.arguments as? Map<String, Any>
                    if (args != null) {
                        val type = args["type"] as? String
                        if (type == "quiz") updateQuizNotification(args) else updateTodoNotification(args)
                        result.success(null)
                    } else result.error("INVALID_ARGS", "Arguments were null", null)
                }
                "cancelNotification" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancel(NOTIFICATION_ID)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 屏幕时间通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_TIME_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkUsagePermission" -> result.success(hasUsageStatsPermission())
                "openUsageSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                "getScreenTimeData" -> result.success(getUsageStats())
                else -> result.notImplemented()
            }
        }
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun getUsageStats(): List<Map<String, Any>> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()

        val stats = usageStatsManager.queryAndAggregateUsageStats(startTime, endTime)
        val pm = packageManager
        val result = mutableListOf<Map<String, Any>>()

        for ((pkgName, usageStat) in stats) {
            val totalTime = usageStat.totalTimeInForeground
            if (totalTime > 60000) { // 仅上报使用超过1分钟的应用
                val label = try {
                    val info = pm.getApplicationInfo(pkgName, 0)
                    pm.getApplicationLabel(info).toString()
                } catch (e: Exception) { pkgName }

                val appMap = mutableMapOf<String, Any>()
                appMap["app_name"] = label
                appMap["duration"] = (totalTime / 1000 / 60).toInt()
                result.add(appMap)
            }
        }
        return result
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // --- 清理旧渠道开始 ---
            val oldChannelIds = listOf("live_updates_official", "live_updates_demo", "order_updates")
            for (oldId in oldChannelIds) {
                notificationManager.deleteNotificationChannel(oldId)
            }
            // --- 清理旧渠道结束 ---

            val name = "Live Activities"
            val descriptionText = "Shows ongoing tasks and quizzes"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setSound(null, null)
                enableVibration(false)
                setShowBadge(true)
            }

            notificationManager.createNotificationChannel(channel)
        }
    }

    // === 处理数学测验的通知逻辑 ===
    private fun updateQuizNotification(args: Map<String, Any>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val currentIndex = (args["currentIndex"] as? Number)?.toInt() ?: 0
        val totalCount = (args["totalCount"] as? Number)?.toInt() ?: 10
        val questionText = args["questionText"] as? String ?: "Ready..."
        val isOver = args["isOver"] as? Boolean ?: false
        val score = (args["score"] as? Number)?.toInt() ?: 0

        // 计算进度：如果结束了就是100%，否则按题号计算
        val progress = if (isOver) 100 else if (totalCount > 0) ((currentIndex) * 100) / totalCount else 0

        val title: String
        val text: String
        val subText: String
        val color: Int

        if (isOver) {
            title = "Quiz Finished! 🏆"
            text = "Final Score: $score / ${totalCount * 10}"
            subText = "Completed"
            color = 0xFFF4B400.toInt() // 金黄色
        } else {
            // 题号+1 因为索引从0开始
            title = "Question ${currentIndex + 1} of $totalCount"
            text = questionText // 例如 "15 + 3 = ?"
            subText = "Math Quiz"
            color = 0xFF673AB7.toInt() // 深紫色
        }

        // 构建通知
        buildAndNotify(title, text, subText, progress, !isOver, color)
    }

    // === 处理待办事项的通知逻辑 ===
    private fun updateTodoNotification(args: Map<String, Any>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val totalCount = (args["totalCount"] as? Number)?.toInt() ?: 0
        val completedCount = (args["completedCount"] as? Number)?.toInt() ?: 0
        val pendingTitlesRaw = args["pendingTitles"] as? List<*>
        val pendingTitles = pendingTitlesRaw?.filterIsInstance<String>() ?: emptyList()

        val isAllDone = completedCount == totalCount && totalCount > 0
        val progress = if (totalCount > 0) (completedCount * 100) / totalCount else 0

        val title: String
        val text: String
        val subText = "$completedCount/$totalCount Done"
        val color: Int

        if (isAllDone) {
            title = "All Tasks Completed! 🎉"
            text = "Great job clearing your list."
            color = 0xFF0F9D58.toInt() // 绿色
        } else {
            title = if (pendingTitles.isNotEmpty()) "Current: ${pendingTitles[0]}" else "Keep Going!"
            text = if (pendingTitles.size > 1) {
                "Next: ${pendingTitles.drop(1).joinToString(", ")}"
            } else {
                "Almost there!"
            }
            color = 0xFF4285F4.toInt() // 蓝色
        }

        buildAndNotify(title, text, subText, progress, !isAllDone, color)
    }

    // === 通用构建方法 ===
    private fun buildAndNotify(title: String, text: String, subText: String, progress: Int, isOngoing: Boolean, color: Int) {
        val context = this
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // === 关键修复 ===
        // 之前使用了 FLAG_ACTIVITY_CLEAR_TASK，会导致应用重启回到首页。
        // 现在改为 FLAG_ACTIVITY_SINGLE_TOP，如果应用在后台，它会直接将应用拉回前台而不重建。
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }

        val pendingIntent: PendingIntent = PendingIntent.getActivity(
            context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val iconRes = R.mipmap.ic_launcher

        val builder = Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(iconRes)
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

        // 大图处理（可选）
        try {
            val largeIcon = BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
            if (largeIcon != null) {
                builder.setLargeIcon(Icon.createWithBitmap(largeIcon))
            }
        } catch (e: Exception) {}

        val extras = Bundle()
        extras.putBoolean("android.extra.requestPromotedOngoing", true)
        builder.addExtras(extras)

        try {
            notificationManager.notify(NOTIFICATION_ID, builder.build())
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission error", e)
        }
    }
}