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
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class NotificationPollWorker(
    private val appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "NotificationPollWorker"
        const val CHANNEL_ID = "important_background_notifications"
        const val PREFS_NAME = "background_notification_prefs"

        const val KEY_USER_ID = "user_id"
        const val KEY_TOKEN = "token"
        const val KEY_API_BASE_URL = "api_base_url"
        const val KEY_LAST_EVENT_ID = "last_notification_event_id"
        const val KEY_UNREAD_CACHE = "unread_notification_cache"
        const val KEY_SHOWN_EVENT_IDS = "shown_notification_event_ids"
    }

    override suspend fun doWork(): Result {
        return try {
            val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            val userId = prefs.getLong(KEY_USER_ID, -1L)
            val token = prefs.getString(KEY_TOKEN, null)
            val apiBaseUrl = prefs.getString(KEY_API_BASE_URL, null)
            val lastEventId = prefs.getLong(KEY_LAST_EVENT_ID, 0L)

            if (userId <= 0 || token.isNullOrBlank() || apiBaseUrl.isNullOrBlank()) {
                Log.d(TAG, "Skip poll: missing config userId=$userId hasToken=${!token.isNullOrBlank()} apiBaseUrl=$apiBaseUrl")
                return Result.success()
            }

            Log.d(TAG, "Start poll userId=$userId afterId=$lastEventId base=$apiBaseUrl")
            val responseText = requestNotifications(
                apiBaseUrl = apiBaseUrl,
                userId = userId,
                afterId = lastEventId,
                token = token
            )

            val json = JSONObject(responseText)
            if (!json.optBoolean("success", false)) {
                Log.w(TAG, "Poll response success=false")
                return Result.retry()
            }

            val events = json.optJSONArray("events") ?: JSONArray()
            Log.d(TAG, "Poll success events=${events.length()} latest=${json.optLong("latest_id", lastEventId)}")
            if (events.length() == 0) {
                val latestId = json.optLong("latest_id", lastEventId)
                if (latestId > lastEventId) {
                    prefs.edit().putLong(KEY_LAST_EVENT_ID, latestId).apply()
                }
                return Result.success()
            }

            createNotificationChannel()

            var maxEventId = lastEventId
            val shownEventIds = prefs.getStringSet(KEY_SHOWN_EVENT_IDS, emptySet()) ?: emptySet()
            for (i in 0 until events.length()) {
                val event = events.getJSONObject(i)
                val eventId = event.optLong("id", 0L)
                if (eventId <= lastEventId) continue

                if (eventId > maxEventId) maxEventId = eventId

                val eventType = event.optString("event_type", "")
                val title = event.optString("title", "新的通知")
                val body = event.optString("body", "")
                val payload = event.optJSONObject("payload")?.toString()
                    ?: event.optString("payload", "{}")

                if (!shownEventIds.contains(eventId.toString())) {
                    saveUnreadToLocalCache(
                        eventId = eventId,
                        eventType = eventType,
                        title = title,
                        body = body,
                        payload = payload
                    )

                    if (canPostNotification()) {
                        Log.d(TAG, "Show notification eventId=$eventId type=$eventType title=$title")
                        showNotification(eventId = eventId, title = title, body = body)
                    } else {
                        Log.d(TAG, "Cache unread only: notification permission denied eventId=$eventId")
                    }
                } else {
                    Log.d(TAG, "Skip already shown eventId=$eventId")
                }
            }

            prefs.edit().putLong(KEY_LAST_EVENT_ID, maxEventId).apply()
            Result.success()
        } catch (e: Exception) {
            Log.w(TAG, "Poll failed", e)
            Result.retry()
        }
    }

    private fun requestNotifications(
        apiBaseUrl: String,
        userId: Long,
        afterId: Long,
        token: String
    ): String {
        val base = apiBaseUrl.trimEnd('/')
        val url = URL("$base/api/notifications/poll?user_id=$userId&after_id=$afterId")
        val connection = url.openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
        connection.connectTimeout = 8000
        connection.readTimeout = 8000
        connection.setRequestProperty("Authorization", "Bearer $token")
        connection.setRequestProperty("Accept", "application/json")

        val code = connection.responseCode
        val stream = if (code in 200..299) connection.inputStream else connection.errorStream
        val text = stream.bufferedReader().use { it.readText() }
        connection.disconnect()

        if (code !in 200..299) {
            throw RuntimeException("Poll failed: HTTP $code")
        }
        return text
    }

    private fun canPostNotification(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "重要后台通知",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "团队申请、团队公告、重要提醒"
        }
        manager.createNotificationChannel(channel)
    }

    private fun showNotification(eventId: Long, title: String, body: String) {
        val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val intent = Intent(appContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            appContext,
            eventId.toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        manager.notify(eventId.toInt(), notification)
    }

    private fun saveUnreadToLocalCache(
        eventId: Long,
        eventType: String,
        title: String,
        body: String,
        payload: String
    ) {
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val oldText = prefs.getString(KEY_UNREAD_CACHE, "[]") ?: "[]"
        val array = try {
            JSONArray(oldText)
        } catch (_: Exception) {
            JSONArray()
        }

        for (i in 0 until array.length()) {
            if (array.optJSONObject(i)?.optLong("id") == eventId) return
        }

        val item = JSONObject().apply {
            put("id", eventId)
            put("event_type", eventType)
            put("title", title)
            put("body", body)
            put("payload", payload)
            put("received_at", System.currentTimeMillis())
        }
        array.put(item)
        prefs.edit().putString(KEY_UNREAD_CACHE, array.toString()).apply()
    }
}
