package com.math_quiz.junpgle.com.math_quiz_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 闹钟触发接收器：AlarmManager 精确唤醒后，由此 Receiver 启动 ReminderService。
 * 也兼任 BOOT_COMPLETED 接收器——开机后重新注册所有 Alarm。
 */
class ReminderAlarmReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_FIRE   = "com.math_quiz.ACTION_REMINDER_FIRE"
        const val ACTION_RESCHEDULE = "com.math_quiz.ACTION_RESCHEDULE"
        const val TAG = "ReminderAlarm"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "onReceive: ${intent.action}")
        when (intent.action) {
            ACTION_FIRE -> {
                // 精确时刻到达：启动前台 Service 发出通知
                val svcIntent = Intent(context, ReminderService::class.java).apply {
                    action = ReminderService.ACTION_SHOW_REMINDER
                    // 将所有 Extras 透传给 Service
                    putExtras(intent)
                }
                context.startForegroundService(svcIntent)
            }

            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            ACTION_RESCHEDULE -> {
                // 开机/更新后：重新注册所有 Alarm（由 ReminderService 负责读取本地数据并调度）
                val svcIntent = Intent(context, ReminderService::class.java).apply {
                    action = ReminderService.ACTION_RESCHEDULE
                }
                context.startForegroundService(svcIntent)
            }
        }
    }
}

