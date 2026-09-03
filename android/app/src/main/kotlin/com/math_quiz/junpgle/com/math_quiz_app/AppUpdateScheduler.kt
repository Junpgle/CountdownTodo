package com.math_quiz.junpgle.com.math_quiz_app

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * 注册每天一次的应用更新检查。
 *
 * WorkManager 会持久化任务，并在设备重启后恢复。实际执行时间可能因系统
 * 省电策略产生少量偏移，这是 Android 后台定时任务的正常行为。
 */
object AppUpdateScheduler {
    private const val TAG = "AppUpdateScheduler"
    private const val WORK_NAME = "daily_app_update_check"
    private const val CHECK_HOUR = 9
    private const val CHECK_MINUTE = 0

    fun scheduleDailyCheck(context: Context) {
        val request = PeriodicWorkRequestBuilder<AppUpdateWorker>(
            24,
            TimeUnit.HOURS
        )
            .setInitialDelay(delayUntilNextCheck(), TimeUnit.MILLISECONDS)
            .setConstraints(
                Constraints.Builder()
                    // 更新包较大，只在非计费网络（通常为 Wi-Fi）上执行。
                    .setRequiredNetworkType(NetworkType.UNMETERED)
                    .setRequiresBatteryNotLow(true)
                    .build()
            )
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                30,
                TimeUnit.MINUTES
            )
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request
        )
        Log.d(TAG, "Scheduled daily app update check")
    }

    private fun delayUntilNextCheck(now: Calendar = Calendar.getInstance()): Long {
        val next = now.clone() as Calendar
        next.set(Calendar.HOUR_OF_DAY, CHECK_HOUR)
        next.set(Calendar.MINUTE, CHECK_MINUTE)
        next.set(Calendar.SECOND, 0)
        next.set(Calendar.MILLISECOND, 0)
        if (!next.after(now)) {
            next.add(Calendar.DAY_OF_YEAR, 1)
        }
        return (next.timeInMillis - now.timeInMillis).coerceAtLeast(0L)
    }
}
