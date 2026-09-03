package com.math_quiz.junpgle.com.math_quiz_app

internal data class AndroidPomodoroTimerSpec(
    val anchorTimeMs: Long,
    val countsDown: Boolean
)

/** Pure policy decisions shared by Android energy-sensitive components. */
internal object AndroidEnergyPolicy {
    const val IMMEDIATE_NOTIFICATION_POLL_MIN_INTERVAL_MS = 15 * 60 * 1000L
    const val HIGH_REFRESH_IDLE_TIMEOUT_MS = 2500L

    fun shouldEnqueueImmediateNotificationPoll(
        lastEnqueuedAtMs: Long,
        nowMs: Long,
        force: Boolean
    ): Boolean {
        if (force || lastEnqueuedAtMs <= 0L) return true

        val elapsedMs = nowMs - lastEnqueuedAtMs
        // Treat a wall-clock rollback as stale instead of suppressing polling
        // indefinitely behind a timestamp that is now in the future.
        return elapsedMs < 0L ||
            elapsedMs >= IMMEDIATE_NOTIFICATION_POLL_MIN_INTERVAL_MS
    }

    fun shouldRequestHighRefreshRate(
        isPowerSaveMode: Boolean,
        isThermallyConstrained: Boolean
    ): Boolean = !isPowerSaveMode && !isThermallyConstrained

    fun shouldRescheduleReminderSchedule(
        existingJson: String,
        incomingJson: String,
        clearFirst: Boolean,
        forceReschedule: Boolean
    ): Boolean {
        if (forceReschedule || !clearFirst) return true
        return existingJson != incomingJson
    }

    fun resolvePomodoroTimer(
        timerMode: String?,
        timerAnchorMs: Long,
        isPaused: Boolean,
        nowMs: Long
    ): AndroidPomodoroTimerSpec? {
        if (isPaused || timerAnchorMs <= 0L) return null

        return when (timerMode) {
            "countdown" -> if (timerAnchorMs > nowMs) {
                AndroidPomodoroTimerSpec(
                    anchorTimeMs = timerAnchorMs,
                    countsDown = true
                )
            } else {
                null
            }

            "countUp" -> if (timerAnchorMs <= nowMs) {
                AndroidPomodoroTimerSpec(
                    anchorTimeMs = timerAnchorMs,
                    countsDown = false
                )
            } else {
                null
            }

            else -> null
        }
    }
}
