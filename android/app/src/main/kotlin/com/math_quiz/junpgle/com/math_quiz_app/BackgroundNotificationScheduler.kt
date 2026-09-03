package com.math_quiz.junpgle.com.math_quiz_app

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

object BackgroundNotificationScheduler {
    private const val TAG = "BgNotifyScheduler"
    private const val IMPORTANT_WORK_NAME = "important_notification_poll"
    private const val IMMEDIATE_WORK_NAME = "important_notification_poll_once"

    fun startImportantNotificationPoll(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()

        val request = PeriodicWorkRequestBuilder<NotificationPollWorker>(
            15,
            TimeUnit.MINUTES
        )
            .setConstraints(constraints)
            .setInputData(
                workDataOf(NotificationPollWorker.KEY_SKIP_WHEN_APP_VISIBLE to true)
            )
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                10,
                TimeUnit.MINUTES
            )
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            IMPORTANT_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request
        )
        Log.d(TAG, "Scheduled periodic notification poll")
    }

    fun runImmediateNotificationPoll(context: Context, force: Boolean = false): Boolean {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(
            NotificationPollWorker.PREFS_NAME,
            Context.MODE_PRIVATE
        )
        val nowMs = System.currentTimeMillis()
        val lastEnqueuedAtMs = prefs.getLong(
            NotificationPollWorker.KEY_LAST_IMMEDIATE_POLL_ENQUEUED_AT,
            0L
        )
        if (!AndroidEnergyPolicy.shouldEnqueueImmediateNotificationPoll(
                lastEnqueuedAtMs = lastEnqueuedAtMs,
                nowMs = nowMs,
                force = force
            )
        ) {
            Log.d(TAG, "Skip duplicate immediate notification poll")
            return false
        }

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val request = OneTimeWorkRequestBuilder<NotificationPollWorker>()
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(appContext).enqueueUniqueWork(
            IMMEDIATE_WORK_NAME,
            ExistingWorkPolicy.KEEP,
            request
        )
        prefs.edit()
            .putLong(NotificationPollWorker.KEY_LAST_IMMEDIATE_POLL_ENQUEUED_AT, nowMs)
            .apply()
        Log.d(TAG, "Enqueued immediate notification poll force=$force")
        return true
    }

    fun stopImportantNotificationPoll(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(IMPORTANT_WORK_NAME)
        WorkManager.getInstance(context).cancelUniqueWork(IMMEDIATE_WORK_NAME)
        context.applicationContext.getSharedPreferences(
            NotificationPollWorker.PREFS_NAME,
            Context.MODE_PRIVATE
        ).edit()
            .remove(NotificationPollWorker.KEY_LAST_IMMEDIATE_POLL_ENQUEUED_AT)
            .apply()
        Log.d(TAG, "Cancelled notification poll work")
    }
}
