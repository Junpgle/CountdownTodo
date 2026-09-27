package com.math_quiz.junpgle.com.math_quiz_app

import android.app.AlarmManager
import android.app.AutomaticZenRule
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.notification.Condition
import android.util.Log

/**
 * Owns the Android system Do Not Disturb rule for a CountDownTodo focus
 * session. Android Q and newer use an app-owned AutomaticZenRule, so ending a
 * focus session cannot overwrite a manual DND choice made by the user. Older
 * Android versions use the interruption-filter fallback, and an alarm
 * provides best-effort cleanup if the Flutter process is killed.
 */
object SystemDoNotDisturbManager {
    private const val TAG = "SystemDoNotDisturb"
    private const val PREFS_NAME = "focus_system_dnd"
    private const val KEY_OWNED = "owned"
    private const val KEY_ORIGINAL_FILTER = "original_filter"
    private const val KEY_AUTOMATIC_RULE_ID = "automatic_rule_id"
    private const val RULE_NAME = "CountDownTodo 专注勿扰"
    private const val RULE_PATH = "focus_dnd"
    private const val RESTORE_REQUEST_CODE = 49903
    private const val ACTION_RESTORE = "com.math_quiz.RESTORE_SYSTEM_DND"
    private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
    private const val FLUTTER_DND_ACTIVE = "flutter.focus_do_not_disturb_active"
    private const val FLUTTER_DND_UNTIL = "flutter.focus_do_not_disturb_until_ms"
    private const val FLUTTER_DND_SESSION = "flutter.focus_do_not_disturb_session_uuid"

    fun hasAccess(context: Context): Boolean {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return try {
            manager.isNotificationPolicyAccessGranted
        } catch (_: SecurityException) {
            false
        }
    }

    fun setEnabled(context: Context, enabled: Boolean, untilMs: Long?): Boolean {
        if (!hasAccess(context)) return false
        return if (enabled) enable(context, untilMs) else restoreIfOwned(context)
    }

    fun restoreIfOwned(context: Context): Boolean {
        if (!hasAccess(context)) return false

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_OWNED, false)) {
            cancelRestoreAlarm(context)
            return true
        }

        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // This only deactivates CountDownTodo's own rule. Any manual
                // DND state or another app's automatic rule remains intact.
                val ruleId = prefs.getString(KEY_AUTOMATIC_RULE_ID, null)
                if (!ruleId.isNullOrBlank() &&
                    manager.getAutomaticZenRule(ruleId) != null
                ) {
                    manager.setAutomaticZenRuleState(
                        ruleId,
                        buildCondition(context, Condition.STATE_FALSE)
                    )
                }
            } else {
                restoreLegacyInterruptionFilter(manager, prefs)
            }
            clearOwnedState(context, prefs)
            cancelRestoreAlarm(context)
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "Unable to restore the previous interruption filter", e)
            false
        }
    }

    fun shouldSuppressNotification(
        context: Context,
        type: String?,
        notifId: Int
    ): Boolean {
        if (!isAppDoNotDisturbActive(context)) return false
        return type != "pomodoro" &&
            type != "pomodoro_end" &&
            notifId !in 40001..40002
    }

    fun isAppDoNotDisturbActive(context: Context): Boolean {
        val prefs =
            context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(FLUTTER_DND_ACTIVE, false)) return false
        val untilMs = prefs.getLong(FLUTTER_DND_UNTIL, 0L)
        return untilMs <= 0L || untilMs > System.currentTimeMillis()
    }

    /**
     * Returns whether a fired alarm is the current countdown's focus-end
     * alarm. A stale alarm (for example one that fired after a pause) must not
     * turn off DND for a still-running session.
     */
    fun isCurrentFocusEndReminder(
        context: Context,
        sessionUuid: String?,
        triggerAtMs: Long
    ): Boolean {
        if (triggerAtMs <= 0L || !isAppDoNotDisturbActive(context)) return false

        val prefs =
            context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        val storedSession = prefs.getString(FLUTTER_DND_SESSION, null)
        if (sessionUuid != null &&
            storedSession != null &&
            sessionUuid != storedSession
        ) {
            return false
        }

        val untilMs = prefs.getLong(FLUTTER_DND_UNTIL, 0L)
        // Countdown DND uses the exact target end as its expiry. Paused and
        // count-up sessions use a rolling safety timeout instead, so an old
        // countdown alarm cannot end them accidentally.
        return untilMs > 0L && kotlin.math.abs(untilMs - triggerAtMs) <= 5_000L
    }

    private fun enable(context: Context, untilMs: Long?): Boolean {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val ruleId = getOrCreateAutomaticRule(context, manager, prefs)
                    ?: return false
                manager.setAutomaticZenRuleState(
                    ruleId,
                    buildCondition(context, Condition.STATE_TRUE)
                )
            } else {
                val alreadyOwned = prefs.getBoolean(KEY_OWNED, false)
                val original = if (alreadyOwned) {
                    prefs.getInt(
                        KEY_ORIGINAL_FILTER,
                        NotificationManager.INTERRUPTION_FILTER_ALL
                    )
                } else {
                    manager.currentInterruptionFilter
                }
                manager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
                if (!alreadyOwned) {
                    prefs.edit()
                        .putBoolean(KEY_OWNED, true)
                        .putInt(KEY_ORIGINAL_FILTER, original)
                        .apply()
                }
            }
            prefs.edit().putBoolean(KEY_OWNED, true).apply()
            scheduleRestoreAlarm(context, untilMs)
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "Unable to enable system Do Not Disturb", e)
            false
        }
    }

    private fun getOrCreateAutomaticRule(
        context: Context,
        manager: NotificationManager,
        prefs: android.content.SharedPreferences
    ): String? {
        val storedId = prefs.getString(KEY_AUTOMATIC_RULE_ID, null)
        if (!storedId.isNullOrBlank() && manager.getAutomaticZenRule(storedId) != null) {
            return storedId
        }

        val conditionId = buildConditionId(context)
        val existing = manager.automaticZenRules.entries.firstOrNull { entry ->
            val rule = entry.value
            rule.conditionId == conditionId &&
                rule.configurationActivity ==
                ComponentName(context, MainActivity::class.java)
        }
        if (existing != null) {
            prefs.edit().putString(KEY_AUTOMATIC_RULE_ID, existing.key).apply()
            return existing.key
        }

        // The null owner is intentional: this rule reports its state with
        // NotificationManager.setAutomaticZenRuleState rather than through a
        // ConditionProviderService. MainActivity is supplied as the required
        // configuration activity so Android can present the rule to the user.
        val rule = AutomaticZenRule(
            RULE_NAME,
            null,
            ComponentName(context, MainActivity::class.java),
            conditionId,
            null,
            NotificationManager.INTERRUPTION_FILTER_NONE,
            true
        )
        val id = manager.addAutomaticZenRule(rule)
        if (!id.isNullOrBlank()) {
            prefs.edit().putString(KEY_AUTOMATIC_RULE_ID, id).apply()
        }
        return id
    }

    private fun buildConditionId(context: Context): Uri {
        return Condition.newId(context).appendPath(RULE_PATH).build()
    }

    private fun buildCondition(context: Context, state: Int): Condition {
        return Condition(
            buildConditionId(context),
            RULE_NAME,
            state
        )
    }

    private fun restoreLegacyInterruptionFilter(
        manager: NotificationManager,
        prefs: android.content.SharedPreferences
    ) {
        val current = manager.currentInterruptionFilter
        val original = prefs.getInt(
            KEY_ORIGINAL_FILTER,
            NotificationManager.INTERRUPTION_FILTER_ALL
        )
        // If the user changed the filter away from NONE, keep the newer user
        // choice. This is the best ownership boundary available on API 26-28;
        // API 29+ uses an isolated automatic rule instead.
        if (current == NotificationManager.INTERRUPTION_FILTER_NONE) {
            manager.setInterruptionFilter(original)
        }
    }

    private fun clearOwnedState(
        context: Context,
        prefs: android.content.SharedPreferences
    ) {
        // Keep the rule id so the next focus session reuses the same visible
        // system rule instead of creating another entry in Settings.
        prefs.edit()
            .remove(KEY_OWNED)
            .remove(KEY_ORIGINAL_FILTER)
            .apply()

        // A background restore alarm can run without Flutter. Clear the Dart
        // marker as well, otherwise the next app start could re-enable a stale
        // system rule before it has loaded the run state.
        context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(FLUTTER_DND_ACTIVE, false)
            .remove(FLUTTER_DND_UNTIL)
            .remove(FLUTTER_DND_SESSION)
            .apply()
    }

    private fun scheduleRestoreAlarm(context: Context, untilMs: Long?) {
        val now = System.currentTimeMillis()
        val requested = untilMs ?: 0L
        val triggerAt = if (requested > now) requested else now + 12 * 60 * 60 * 1000L
        val intent = Intent(context, FocusDoNotDisturbRestoreReceiver::class.java).apply {
            action = ACTION_RESTORE
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            RESTORE_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                alarmManager.canScheduleExactAlarms()
            ) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pendingIntent
                )
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Unable to schedule system DND restore alarm", e)
        }
    }

    private fun cancelRestoreAlarm(context: Context) {
        val intent = Intent(context, FocusDoNotDisturbRestoreReceiver::class.java).apply {
            action = ACTION_RESTORE
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            RESTORE_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        ) ?: return
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }
}

class FocusDoNotDisturbRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == "com.math_quiz.RESTORE_SYSTEM_DND") {
            SystemDoNotDisturbManager.restoreIfOwned(context)
        }
    }
}
