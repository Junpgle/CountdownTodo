package com.math_quiz.junpgle.com.math_quiz_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles countdown special-date notification "完成" clicks and manual
 * swipe-dismissals even when MainActivity is in the background or destroyed.
 */
class CountdownReminderReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_COMPLETE = "com.math_quiz.ACTION_COUNTDOWN_COMPLETE"
        const val ACTION_DISMISS = "com.math_quiz.ACTION_COUNTDOWN_DISMISS"
        const val INTERNAL_ACTION_COMPLETED = "com.math_quiz.INTERNAL_COUNTDOWN_COMPLETED"
        const val INTERNAL_ACTION_DISMISSED = "com.math_quiz.INTERNAL_COUNTDOWN_DISMISSED"

        const val EXTRA_NOTIFICATION_ID = "notification_id"
        const val EXTRA_NOTIFICATION_IDS = "notification_ids"
        const val EXTRA_COUNTDOWN_ID = "countdown_id"
        const val EXTRA_DATE_STR = "date_str"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val notifId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        val countdownId = intent.getStringExtra(EXTRA_COUNTDOWN_ID)
        val dateStr = CountdownReminderStore.normalizeDateStr(
            intent.getStringExtra(EXTRA_DATE_STR)
        )

        when (intent.action) {
            ACTION_COMPLETE -> {
                if (notifId == -1 && countdownId.isNullOrBlank()) return
                val cancelledIds = CountdownReminderStore.markCompletedFromAction(
                    context = context,
                    countdownId = countdownId,
                    notifId = notifId,
                    dateStr = dateStr
                )
                val notifyMainIntent = Intent(INTERNAL_ACTION_COMPLETED).apply {
                    setPackage(context.packageName)
                    putExtra(EXTRA_NOTIFICATION_ID, notifId)
                    putExtra(EXTRA_NOTIFICATION_IDS, cancelledIds.toIntArray())
                    if (!countdownId.isNullOrBlank()) {
                        putExtra(EXTRA_COUNTDOWN_ID, countdownId)
                    }
                    putExtra(EXTRA_DATE_STR, dateStr)
                }
                context.sendBroadcast(notifyMainIntent)
            }

            ACTION_DISMISS -> {
                if (notifId == -1 && countdownId.isNullOrBlank()) return
                CountdownReminderStore.markDismissed(
                    context = context,
                    countdownId = countdownId,
                    notifId = notifId,
                    dateStr = dateStr
                )
                val notifyMainIntent = Intent(INTERNAL_ACTION_DISMISSED).apply {
                    setPackage(context.packageName)
                    putExtra(EXTRA_NOTIFICATION_ID, notifId)
                    if (!countdownId.isNullOrBlank()) {
                        putExtra(EXTRA_COUNTDOWN_ID, countdownId)
                    }
                    putExtra(EXTRA_DATE_STR, dateStr)
                }
                context.sendBroadcast(notifyMainIntent)
            }
        }
    }
}
