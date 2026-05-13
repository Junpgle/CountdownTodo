package com.math_quiz.junpgle.com.math_quiz_app

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

object BackgroundNotificationScheduler {
    private const val TAG = "BgNotifyScheduler"
    private const val IMPORTANT_WORK_NAME = "important_notification_poll"
    private const val IMMEDIATE_WORK_NAME = "important_notification_poll_once"

    fun startImportantNotificationPoll(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val request = PeriodicWorkRequestBuilder<NotificationPollWorker>(
            15,
            TimeUnit.MINUTES
        )
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            IMPORTANT_WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request
        )
        Log.d(TAG, "Scheduled periodic notification poll")
    }

    fun runImmediateNotificationPoll(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val request = OneTimeWorkRequestBuilder<NotificationPollWorker>()
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            IMMEDIATE_WORK_NAME,
            androidx.work.ExistingWorkPolicy.REPLACE,
            request
        )
        Log.d(TAG, "Scheduled immediate notification poll")
    }

    fun stopImportantNotificationPoll(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(IMPORTANT_WORK_NAME)
        WorkManager.getInstance(context).cancelUniqueWork(IMMEDIATE_WORK_NAME)
        Log.d(TAG, "Cancelled notification poll work")
    }
}
