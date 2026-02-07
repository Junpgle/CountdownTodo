package com.math_quiz.junpgle.com.math_quiz_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.math_quiz.junpgle.com.math_quiz_app/notifications"
    // Channel ID 保持不变，用于实时活动
    private val NOTIFICATION_CHANNEL_ID = "live_updates_official_v2"
    private val NOTIFICATION_ID = 12345
    private val TAG = "LiveUpdates"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // 接收来自 Flutter 的真实数据更新
                "showOngoingNotification" -> {
                    val args = call.arguments as? Map<String, Any>
                    if (args != null) {
                        updateRealtimeNotification(args)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGS", "Arguments were null", null)
                    }
                }
                "cancelNotification" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancel(NOTIFICATION_ID)
                    result.success(null)
                }
                "checkPromotedNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 35) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        result.success(nm.canPostPromotedNotifications())
                    } else {
                        result.success(true)
                    }
                }
                "openPromotedNotificationSettings" -> {
                    if (Build.VERSION.SDK_INT >= 35) {
                        try {
                            val intent = Intent("android.settings.MANAGE_APP_PROMOTED_NOTIFICATIONS")
                            intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // --- 清理旧渠道开始 ---
            // 删除以前测试可能留下的旧渠道ID，保持设置界面干净
            val oldChannelIds = listOf("live_updates_official", "live_updates_demo", "order_updates")
            for (oldId in oldChannelIds) {
                notificationManager.deleteNotificationChannel(oldId)
            }
            // --- 清理旧渠道结束 ---

            val name = "Todo Live Activity"
            val descriptionText = "Shows your current todo progress"
            // IMPORTANCE_HIGH 是触发状态栏胶囊/灵动岛的关键
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

    // --- 核心逻辑：根据 Flutter 传来的数据更新通知 ---
    private fun updateRealtimeNotification(args: Map<String, Any>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        // 1. 解析数据 (安全转换类型)
        val totalCount = (args["totalCount"] as? Number)?.toInt() ?: 0
        val completedCount = (args["completedCount"] as? Number)?.toInt() ?: 0
        // Flutter 传来的 List<String> 可能会被转为 ArrayList
        val pendingTitlesRaw = args["pendingTitles"] as? List<*>
        val pendingTitles = pendingTitlesRaw?.filterIsInstance<String>() ?: emptyList()

        // 2. 状态判断
        val isAllDone = completedCount == totalCount && totalCount > 0
        val progress = if (totalCount > 0) (completedCount * 100) / totalCount else 0

        // 3. 动态文案生成
        val title: String
        val text: String
        val subText = "$completedCount/$totalCount Done"
        val iconRes: Int
        val color: Int

        if (isAllDone) {
            title = "All Tasks Completed! 🎉"
            text = "Great job clearing your list."
            iconRes = R.mipmap.ic_launcher // 完成时可以用 App 图标或勾选图标
            color = 0xFF0F9D58.toInt() // 绿色
        } else {
            // 如果还有任务，取第一个作为标题 (Current Focus)
            title = if (pendingTitles.isNotEmpty()) "Current: ${pendingTitles[0]}" else "Keep Going!"

            // 取后续的任务作为正文预览
            text = if (pendingTitles.size > 1) {
                "Next: ${pendingTitles.drop(1).joinToString(", ")}"
            } else {
                "Almost there!"
            }

            // 默认图标，如果没有 shopping_bag 请确保 res/drawable 下有该资源，或者改回 ic_launcher
            // 为了防止报错，这里先用系统自带的或者 ic_launcher，如果你添加了图标可改为 R.drawable.shopping_bag
            iconRes = R.mipmap.ic_launcher
            color = 0xFF4285F4.toInt() // 蓝色
        }

        // 4. 构建通知
        val context = this
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 点击通知跳转回 App
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent: PendingIntent = PendingIntent.getActivity(
            context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // 尝试加载大图 (可选)
        val largeIcon = try {
            BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
        } catch (e: Exception) { null }

        val builder = Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(iconRes) // 状态栏小图标
            .setContentTitle(title)
            .setContentText(text)
            .setSubText(subText) // 胶囊上的关键文字

            // 进度条
            .setProgress(100, progress, false)

            // 实时活动关键配置
            .setOngoing(!isAllDone) // 只有未完成时才驻留
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setShowWhen(false)

            // 样式
            .setColor(color)
            .setColorized(true) // 必须为 true 才能变色
            .setContentIntent(pendingIntent)

        if (largeIcon != null) {
            builder.setLargeIcon(Icon.createWithBitmap(largeIcon))
        }

        // Android 15 权限提升请求
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