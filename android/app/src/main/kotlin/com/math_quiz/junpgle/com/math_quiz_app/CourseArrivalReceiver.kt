package com.math_quiz.junpgle.com.math_quiz_app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Dismisses the course notification after the user confirms arrival. */
class CourseArrivalReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_MARK_ARRIVED = "com.math_quiz.ACTION_COURSE_ARRIVED"
        const val EXTRA_NOTIFICATION_ID = "course_notification_id"
        const val LIVE_COURSE_NOTIFICATION_ID = 12347
        const val FIRST_SCHEDULED_COURSE_NOTIFICATION_ID = 31001
        const val LAST_SCHEDULED_COURSE_NOTIFICATION_ID = 31999
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_MARK_ARRIVED) return

        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        val isCourseNotification = notificationId == LIVE_COURSE_NOTIFICATION_ID ||
            notificationId in FIRST_SCHEDULED_COURSE_NOTIFICATION_ID..LAST_SCHEDULED_COURSE_NOTIFICATION_ID
        if (!isCourseNotification) return

        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(notificationId)
    }
}
