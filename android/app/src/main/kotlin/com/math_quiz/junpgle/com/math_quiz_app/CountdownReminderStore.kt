package com.math_quiz.junpgle.com.math_quiz_app

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal data class CountdownCategoryStyle(
    val iconResId: Int,
    val color: Int,
    val label: String
)

/**
 * Persists per-day shown/dismissed state and native completion queue for
 * countdown special-date reminders so manual swipe-dismissal and notification
 * "完成" actions survive Activity/process restarts.
 */
internal object CountdownReminderStore {
    private const val PREFS_NAME = "countdown_reminder_state"
    private const val KEY_DISMISSED_KEYS = "dismissed_keys"
    private const val KEY_SHOWN_KEYS = "shown_keys"
    private const val KEY_PENDING_COMPLETED_IDS = "pending_completed_ids"
    private const val KEY_NOTIF_IDS_PREFIX = "notif_ids_"
    private const val ALERT_KEYS_PREFS = "alert_keys"
    private const val ALERT_TODO_ID = 12349
    private const val MAX_RETAINED_KEYS = 200
    private const val COMPLETE_REQUEST_CODE_OFFSET = 400000
    private const val DISMISS_REQUEST_CODE_OFFSET = 500000

    private val lock = Any()

    fun resolveCategoryStyle(
        category: String?,
        compactLabel: Boolean = false
    ): CountdownCategoryStyle {
        val sp = if (compactLabel) "" else " "
        return when (category) {
            "birthday" -> CountdownCategoryStyle(
                R.drawable.ic_countdown_birthday,
                0xFFFF9800.toInt(),
                "🎂${sp}生日"
            )
            "anniversary" -> CountdownCategoryStyle(
                R.drawable.ic_countdown_anniversary,
                0xFFE91E63.toInt(),
                "💖${sp}纪念日"
            )
            "exam" -> CountdownCategoryStyle(
                R.drawable.ic_countdown_exam,
                0xFF3F51B5.toInt(),
                "📝${sp}考试"
            )
            "holiday" -> CountdownCategoryStyle(
                R.drawable.ic_countdown_holiday,
                0xFF00ACC1.toInt(),
                "🌴${sp}假期"
            )
            "travel" -> CountdownCategoryStyle(
                R.drawable.ic_countdown_travel,
                0xFF2196F3.toInt(),
                "✈️${sp}出行"
            )
            "deadline" -> CountdownCategoryStyle(
                R.drawable.ic_countdown_deadline,
                0xFFF44336.toInt(),
                "🚩${sp}重要节点"
            )
            else -> CountdownCategoryStyle(
                R.drawable.hourglass,
                0xFFFF7043.toInt(),
                "⏳${sp}倒数日"
            )
        }
    }

    fun buildKey(countdownId: String?, notifId: Int, dateStr: String): String {
        val cleanId = countdownId?.trim().orEmpty()
        val cleanDate = dateStr.trim()
        val subject = if (cleanId.isNotEmpty()) cleanId else "notif_$notifId"
        return "$subject@$cleanDate"
    }

    fun normalizeDateStr(dateStr: String?, triggerAtMs: Long? = null): String {
        val trimmed = dateStr?.trim().orEmpty()
        if (trimmed.isNotEmpty()) return trimmed
        val ts = if (triggerAtMs != null && triggerAtMs > 0L) {
            triggerAtMs
        } else {
            System.currentTimeMillis()
        }
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(ts))
    }

    fun shouldSuppressPosting(
        isDismissed: Boolean,
        isShown: Boolean,
        isAnyTrackedNotifActive: Boolean
    ): Boolean {
        if (isDismissed) return true
        // If already shown today but no longer present in the shade (e.g.
        // swiped away on a ROM that skips deleteIntent, or auto-cancelled on
        // body tap), do not re-post on app reopen.
        if (isShown && !isAnyTrackedNotifActive) return true
        return false
    }

    fun pruneKeySet(
        keys: Set<String>,
        maxEntries: Int = MAX_RETAINED_KEYS
    ): Set<String> {
        if (keys.size <= maxEntries) return keys
        return keys
            .sortedByDescending { key -> key.substringAfterLast('@', "") }
            .take(maxEntries)
            .toSet()
    }

    fun isNotificationActive(context: Context, notifId: Int): Boolean =
        isAnyNotificationActive(context, setOf(notifId))

    fun isAnyNotificationActive(context: Context, notifIds: Set<Int>): Boolean {
        if (notifIds.isEmpty()) return false
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return false
        return try {
            nm.activeNotifications.any { it.id in notifIds }
        } catch (_: Exception) {
            false
        }
    }

    fun shouldSuppressAndReconcile(
        context: Context,
        countdownId: String?,
        notifId: Int,
        dateStr: String
    ): Boolean {
        val normalizedDate = normalizeDateStr(dateStr)
        val key = buildKey(countdownId, notifId, normalizedDate)
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val dismissed = HashSet(prefs.getStringSet(KEY_DISMISSED_KEYS, emptySet()) ?: emptySet())
            if (dismissed.contains(key)) return true

            val shown = prefs.getStringSet(KEY_SHOWN_KEYS, emptySet()) ?: emptySet()
            if (!shown.contains(key)) return false

            val tracked = readTrackedNotifIds(prefs, key) + notifId
            val active = isAnyNotificationActive(context, tracked)
            val suppress = shouldSuppressPosting(
                isDismissed = false,
                isShown = true,
                isAnyTrackedNotifActive = active
            )
            if (suppress) {
                dismissed.add(key)
                prefs.edit()
                    .putStringSet(KEY_DISMISSED_KEYS, pruneKeySet(dismissed))
                    .apply()
            }
            return suppress
        }
    }

    fun markShown(
        context: Context,
        countdownId: String?,
        notifId: Int,
        dateStr: String
    ) {
        val normalizedDate = normalizeDateStr(dateStr)
        val key = buildKey(countdownId, notifId, normalizedDate)
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val shown = HashSet(prefs.getStringSet(KEY_SHOWN_KEYS, emptySet()) ?: emptySet())
            val prunedShown = pruneKeySet(shown.apply { add(key) })
            val tracked = HashSet(
                prefs.getStringSet("$KEY_NOTIF_IDS_PREFIX$key", emptySet()) ?: emptySet()
            )
            tracked.add(notifId.toString())

            val editor = prefs.edit()
                .putStringSet(KEY_SHOWN_KEYS, prunedShown)
                .putStringSet("$KEY_NOTIF_IDS_PREFIX$key", tracked)
            for (removedKey in shown.subtract(prunedShown)) {
                editor.remove("$KEY_NOTIF_IDS_PREFIX$removedKey")
            }
            editor.apply()
        }
    }

    fun markDismissed(
        context: Context,
        countdownId: String?,
        notifId: Int,
        dateStr: String
    ) {
        val normalizedDate = normalizeDateStr(dateStr)
        val key = buildKey(countdownId, notifId, normalizedDate)
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val dismissed = HashSet(prefs.getStringSet(KEY_DISMISSED_KEYS, emptySet()) ?: emptySet())
            dismissed.add(key)
            prefs.edit()
                .putStringSet(KEY_DISMISSED_KEYS, pruneKeySet(dismissed))
                .apply()
        }
    }

    fun markCompletedFromAction(
        context: Context,
        countdownId: String?,
        notifId: Int,
        dateStr: String
    ): List<Int> {
        val normalizedDate = normalizeDateStr(dateStr)
        val key = buildKey(countdownId, notifId, normalizedDate)
        val cleanCountdownId = countdownId?.trim().orEmpty()
        val idsToCancel: Set<Int>

        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val dismissed = HashSet(prefs.getStringSet(KEY_DISMISSED_KEYS, emptySet()) ?: emptySet())
            dismissed.add(key)
            val editor = prefs.edit()
                .putStringSet(KEY_DISMISSED_KEYS, pruneKeySet(dismissed))

            if (cleanCountdownId.isNotEmpty()) {
                val pending = HashSet(
                    prefs.getStringSet(KEY_PENDING_COMPLETED_IDS, emptySet()) ?: emptySet()
                )
                pending.add(cleanCountdownId)
                editor.putStringSet(KEY_PENDING_COMPLETED_IDS, pending)
            }

            idsToCancel = readTrackedNotifIds(prefs, key) + notifId
            editor.apply()
        }

        cancelNotifications(context, idsToCancel)
        return idsToCancel.toList()
    }

    fun onScheduledCountdownAlarmRemoved(
        context: Context,
        countdownId: String?,
        notifId: Int,
        dateStr: String,
        wasActiveInShade: Boolean
    ) {
        if (!wasActiveInShade) return
        val normalizedDate = normalizeDateStr(dateStr)
        val key = buildKey(countdownId, notifId, normalizedDate)
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val trackedKey = "$KEY_NOTIF_IDS_PREFIX$key"
            val tracked = HashSet(prefs.getStringSet(trackedKey, emptySet()) ?: emptySet())
            tracked.remove(notifId.toString())

            val dismissed = prefs.getStringSet(KEY_DISMISSED_KEYS, emptySet()) ?: emptySet()
            val editor = prefs.edit()
            if (tracked.isEmpty()) {
                editor.remove(trackedKey)
                if (!dismissed.contains(key)) {
                    val shown = HashSet(prefs.getStringSet(KEY_SHOWN_KEYS, emptySet()) ?: emptySet())
                    shown.remove(key)
                    editor.putStringSet(KEY_SHOWN_KEYS, shown)
                }
            } else {
                editor.putStringSet(trackedKey, tracked)
            }
            editor.apply()
        }
    }

    fun cancelStaleAlarmNotifIds(
        context: Context,
        countdownId: String?,
        liveNotifId: Int,
        dateStr: String
    ) {
        val normalizedDate = normalizeDateStr(dateStr)
        val key = buildKey(countdownId, liveNotifId, normalizedDate)
        val alarmIdsToCancel = synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            readTrackedNotifIds(prefs, key)
                .filter { it != liveNotifId && it in 70001..70999 }
                .toSet()
        }
        if (alarmIdsToCancel.isNotEmpty()) {
            cancelNotifications(context, alarmIdsToCancel)
        }
    }

    fun getPendingCompletedIds(context: Context): List<String> {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return (prefs.getStringSet(KEY_PENDING_COMPLETED_IDS, emptySet()) ?: emptySet()).toList()
        }
    }

    fun acknowledgeCompletedIds(context: Context, ids: Collection<String>) {
        if (ids.isEmpty()) return
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val pending = HashSet(
                prefs.getStringSet(KEY_PENDING_COMPLETED_IDS, emptySet()) ?: emptySet()
            )
            if (pending.removeAll(ids.toSet())) {
                prefs.edit().putStringSet(KEY_PENDING_COMPLETED_IDS, pending).apply()
            }
        }
    }

    fun clearStateForCountdown(context: Context, countdownId: String) {
        val cleanId = countdownId.trim()
        if (cleanId.isEmpty()) return
        val prefix = "$cleanId@"
        val idsToCancel = mutableSetOf<Int>()

        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val dismissed = HashSet(prefs.getStringSet(KEY_DISMISSED_KEYS, emptySet()) ?: emptySet())
            val shown = HashSet(prefs.getStringSet(KEY_SHOWN_KEYS, emptySet()) ?: emptySet())
            val pending = HashSet(
                prefs.getStringSet(KEY_PENDING_COMPLETED_IDS, emptySet()) ?: emptySet()
            )

            val matchedKeys = (dismissed + shown).filter { it.startsWith(prefix) }
            val editor = prefs.edit()
            for (key in matchedKeys) {
                idsToCancel.addAll(readTrackedNotifIds(prefs, key))
                editor.remove("$KEY_NOTIF_IDS_PREFIX$key")
            }
            dismissed.removeAll { it.startsWith(prefix) }
            shown.removeAll { it.startsWith(prefix) }
            pending.remove(cleanId)

            editor
                .putStringSet(KEY_DISMISSED_KEYS, dismissed)
                .putStringSet(KEY_SHOWN_KEYS, shown)
                .putStringSet(KEY_PENDING_COMPLETED_IDS, pending)
                .apply()
        }

        if (idsToCancel.isNotEmpty()) {
            cancelNotifications(context, idsToCancel)
        }
    }

    fun createCompletePendingIntent(
        context: Context,
        notifId: Int,
        countdownId: String?,
        dateStr: String
    ): PendingIntent {
        val intent = Intent(context, CountdownReminderReceiver::class.java).apply {
            action = CountdownReminderReceiver.ACTION_COMPLETE
            putExtra(CountdownReminderReceiver.EXTRA_NOTIFICATION_ID, notifId)
            if (!countdownId.isNullOrBlank()) {
                putExtra(CountdownReminderReceiver.EXTRA_COUNTDOWN_ID, countdownId)
            }
            putExtra(CountdownReminderReceiver.EXTRA_DATE_STR, normalizeDateStr(dateStr))
        }
        return PendingIntent.getBroadcast(
            context,
            COMPLETE_REQUEST_CODE_OFFSET + notifId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun createDismissPendingIntent(
        context: Context,
        notifId: Int,
        countdownId: String?,
        dateStr: String
    ): PendingIntent {
        val intent = Intent(context, CountdownReminderReceiver::class.java).apply {
            action = CountdownReminderReceiver.ACTION_DISMISS
            putExtra(CountdownReminderReceiver.EXTRA_NOTIFICATION_ID, notifId)
            if (!countdownId.isNullOrBlank()) {
                putExtra(CountdownReminderReceiver.EXTRA_COUNTDOWN_ID, countdownId)
            }
            putExtra(CountdownReminderReceiver.EXTRA_DATE_STR, normalizeDateStr(dateStr))
        }
        return PendingIntent.getBroadcast(
            context,
            DISMISS_REQUEST_CODE_OFFSET + notifId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun readTrackedNotifIds(
        prefs: android.content.SharedPreferences,
        key: String
    ): Set<Int> {
        val raw = prefs.getStringSet("$KEY_NOTIF_IDS_PREFIX$key", emptySet()) ?: emptySet()
        return raw.mapNotNull { it.toIntOrNull() }.toSet()
    }

    private fun cancelNotifications(context: Context, notifIds: Set<Int>) {
        if (notifIds.isEmpty()) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        for (id in notifIds) {
            try {
                nm.cancel(id)
            } catch (_: Exception) {}
        }

        // Also clear the paired one-time alert notification if it was raised for
        // one of these countdown notification IDs.
        try {
            val alertPrefs = context.getSharedPreferences(ALERT_KEYS_PREFS, Context.MODE_PRIVATE)
            val lastAlertKey = alertPrefs.getString("last_alerted_key_$ALERT_TODO_ID", "") ?: ""
            if (notifIds.any { id -> lastAlertKey.startsWith("countdown_${id}_") }) {
                nm.cancel(ALERT_TODO_ID)
            }
        } catch (_: Exception) {}
    }
}
