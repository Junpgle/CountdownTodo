package com.math_quiz.junpgle.com.math_quiz_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * 不依赖 Flutter 引擎的更新检查任务。
 *
 * 这样即使 App 进程没有启动，WorkManager 也可以直接读取 manifest、比较
 * 当前安装版本并发送系统通知。
 */
class AppUpdateWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "AppUpdateWorker"
        private const val CHANNEL_ID = "app_updates"
        private const val NOTIFICATION_ID = 12354
        private const val PREFS_NAME = "app_update_check"
        private const val KEY_LAST_NOTIFIED_VERSION = "last_notified_version"

        private const val GITHUB_MANIFEST_URL =
            "https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json"
        private const val SERVER_MANIFEST_URL =
            "http://101.200.13.100:8082/api/manifest"
    }

    override suspend fun doWork(): Result {
        return try {
            val manifest = fetchManifest() ?: return Result.retry()
            val remoteVersion = manifest.optString("version_name").trim()
            val localVersion = currentVersionName()

            if (remoteVersion.isEmpty() || localVersion.isEmpty() ||
                compareVersions(remoteVersion, localVersion) <= 0
            ) {
                return Result.success()
            }

            val prefs = applicationContext.getSharedPreferences(
                PREFS_NAME,
                Context.MODE_PRIVATE
            )
            if (prefs.getString(KEY_LAST_NOTIFIED_VERSION, null) == remoteVersion) {
                Log.d(TAG, "Already notified for version $remoteVersion")
                return Result.success()
            }

            if (!canPostNotification()) {
                Log.d(TAG, "Notification permission is unavailable")
                return Result.success()
            }

            showUpdateNotification(remoteVersion, manifest)
            prefs.edit().putString(KEY_LAST_NOTIFIED_VERSION, remoteVersion).apply()
            Result.success()
        } catch (error: Exception) {
            Log.w(TAG, "Update check failed", error)
            Result.retry()
        }
    }

    private fun fetchManifest(): JSONObject? {
        listOf(GITHUB_MANIFEST_URL, SERVER_MANIFEST_URL).forEach { endpoint ->
            try {
                val connection = URL(endpoint).openConnection() as HttpURLConnection
                connection.requestMethod = "GET"
                connection.connectTimeout = 8_000
                connection.readTimeout = 8_000
                connection.setRequestProperty("Accept", "application/json")

                val code = connection.responseCode
                val stream = if (code in 200..299) {
                    connection.inputStream
                } else {
                    connection.errorStream
                }
                val body = stream?.bufferedReader()?.use { it.readText() }
                connection.disconnect()

                if (code in 200..299 && !body.isNullOrBlank()) {
                    return JSONObject(body)
                }
                Log.w(TAG, "Manifest request failed: HTTP $code from $endpoint")
            } catch (error: Exception) {
                Log.w(TAG, "Manifest request failed: $endpoint", error)
            }
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun currentVersionName(): String {
        val packageInfo = applicationContext.packageManager.getPackageInfo(
            applicationContext.packageName,
            0
        )
        return packageInfo.versionName.orEmpty()
    }

    private fun compareVersions(left: String, right: String): Int {
        val leftParts = versionParts(left)
        val rightParts = versionParts(right)
        val count = maxOf(leftParts.size, rightParts.size)
        for (index in 0 until count) {
            val leftPart = leftParts.getOrElse(index) { 0 }
            val rightPart = rightParts.getOrElse(index) { 0 }
            if (leftPart != rightPart) return leftPart.compareTo(rightPart)
        }
        return 0
    }

    private fun versionParts(version: String): List<Int> {
        return version
            .substringBefore('+')
            .substringBefore('-')
            .split('.')
            .map { it.toIntOrNull() ?: 0 }
    }

    private fun canPostNotification(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(
            applicationContext,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun showUpdateNotification(version: String, manifest: JSONObject) {
        val manager = applicationContext.getSystemService(
            Context.NOTIFICATION_SERVICE
        ) as NotificationManager
        createNotificationChannel(manager)

        val updateInfo = manifest.optJSONObject("update_info")
        val title = updateInfo?.optString("title")
            ?.takeIf { it.isNotBlank() }
            ?: "发现新版本"
        val description = updateInfo?.optString("description")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: "CountDownTodo $version 已发布，点击打开应用查看详情"

        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.update)
            .setContentTitle("$title · $version")
            .setContentText(description)
            .setStyle(NotificationCompat.BigTextStyle().bigText(description))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setColor(0xFF0562FD.toInt())
            .build()
        manager.notify(NOTIFICATION_ID, notification)
        Log.d(TAG, "Displayed update notification for $version")
    }

    private fun createNotificationChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "应用更新",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "发现 CountDownTodo 新版本时提醒"
        }
        manager.createNotificationChannel(channel)
    }
}
