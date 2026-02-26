package com.math_quiz.junpgle.com.math_quiz_app

import android.app.*
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
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

        // 1. 通知通道
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

        // 2. 屏幕时间通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_TIME_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkUsagePermission" -> result.success(hasUsageStatsPermission())
                "openUsageSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                "getScreenTimeData" -> {
                    // 直接获取系统底层统计好的数据
                    val data = getSystemAggregatedUsageStats()
                    result.success(data)
                }
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

    /**
     * 直接读取 Android 系统底层的聚合数据 (即手机自带的"屏幕使用时间"数据源)
     * 无需自己遍历事件，完全依赖系统的统计算法。
     */
    private fun getSystemAggregatedUsageStats(): List<Map<String, Any>> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val calendar = Calendar.getInstance()
        // 设置为今天的 00:00:00
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)

        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()

        // 识别设备类型
        val isTablet = (resources.configuration.screenLayout and Configuration.SCREENLAYOUT_SIZE_MASK) >= Configuration.SCREENLAYOUT_SIZE_LARGE
        val deviceType = if (isTablet) "Android-Tablet" else "Android-Phone"

        // 直接向系统请求这段时间的聚合结果
        val statsMap = usageStatsManager.queryAndAggregateUsageStats(startTime, endTime)

        val pm = packageManager
        val usageStatsList = mutableListOf<Map<String, Any>>()

        for ((pkgName, usageStats) in statsMap) {
            // 获取系统统计的"应用在前台显示"的总毫秒数
            val totalTimeMs = usageStats.totalTimeInForeground

            // 过滤掉低于 1 分钟 (60000ms) 的碎片化启动，让图表更干净
            if (totalTimeMs > 60000) {

                // 核心过滤：排除常见的系统服务、桌面启动器和底层组件
                if (pkgName == "android" || pkgName == "com.android.systemui" || pkgName.contains("launcher")) continue

                val label = try {
                    val info = pm.getApplicationInfo(pkgName, 0)
                    pm.getApplicationLabel(info).toString()
                } catch (e: Exception) { pkgName }

                // 如果取不到真正的应用中文名，且是安卓底层系统包，则过滤掉
                if (label == pkgName && pkgName.startsWith("com.android.")) continue

                usageStatsList.add(mapOf(
                    "app_name" to label,
                    "duration" to (totalTimeMs / 1000).toInt(), // 转为秒
                    "device_type" to deviceType
                ))
            }
        }

        return usageStatsList
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val name = "Live Activities"
            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, name, NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    // --- 通知逻辑保持原样 ---
    private fun updateQuizNotification(args: Map<String, Any>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val currentIndex = (args["currentIndex"] as? Number)?.toInt() ?: 0
        val totalCount = (args["totalCount"] as? Number)?.toInt() ?: 10
        val questionText = args["questionText"] as? String ?: "Ready..."
        val isOver = args["isOver"] as? Boolean ?: false
        val score = (args["score"] as? Number)?.toInt() ?: 0

        val progress = if (isOver) 100 else if (totalCount > 0) ((currentIndex) * 100) / totalCount else 0
        val title: String; val text: String; val subText: String; val color: Int
        if (isOver) {
            title = "Quiz Finished! 🏆"; text = "Final Score: $score / ${totalCount * 10}"; subText = "Completed"; color = 0xFFF4B400.toInt()
        } else {
            title = "Question ${currentIndex + 1} of $totalCount"; text = questionText; subText = "Math Quiz"; color = 0xFF673AB7.toInt()
        }

        buildAndNotify(title, text, subText, progress, !isOver, color)
    }

    private fun updateTodoNotification(args: Map<String, Any>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val totalCount = (args["totalCount"] as? Number)?.toInt() ?: 0
        val completedCount = (args["completedCount"] as? Number)?.toInt() ?: 0
        val pendingTitlesRaw = args["pendingTitles"] as? List<*>
        val pendingTitles = pendingTitlesRaw?.filterIsInstance<String>() ?: emptyList()
        val isAllDone = completedCount == totalCount && totalCount > 0
        val progress = if (totalCount > 0) (completedCount * 100) / totalCount else 0
        val title: String; val text: String; val subText = "$completedCount/$totalCount Done"; val color: Int
        if (isAllDone) {
            title = "All Tasks Completed! 🎉"; text = "Great job clearing your list."; color = 0xFF0F9D58.toInt()
        } else {
            title = if (pendingTitles.isNotEmpty()) "Current: ${pendingTitles[0]}" else "Keep Going!"
            text = if (pendingTitles.size > 1) {
                "Next: ${pendingTitles.drop(1).joinToString(", ")}"
            } else {
                "Almost there!"
            }
            color = 0xFF4285F4.toInt()
        }

        buildAndNotify(title, text, subText, progress, !isAllDone, color)
    }

    private fun buildAndNotify(title: String, text: String, subText: String, progress: Int, isOngoing: Boolean, color: Int) {
        val context = this
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val intent = Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP }
        val pendingIntent: PendingIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher).setContentTitle(title).setContentText(text).setSubText(subText).setProgress(100, progress, false)
            .setOngoing(isOngoing).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_STATUS).setVisibility(Notification.VISIBILITY_PUBLIC)
            .setShowWhen(false).setColor(color).setColorized(true).setContentIntent(pendingIntent)
        val extras = Bundle(); extras.putBoolean("android.extra.requestPromotedOngoing", true); builder.addExtras(extras)
        try { notificationManager.notify(NOTIFICATION_ID, builder.build()) } catch (e: Exception) { Log.e(TAG, "Notify error", e) }
    }
}