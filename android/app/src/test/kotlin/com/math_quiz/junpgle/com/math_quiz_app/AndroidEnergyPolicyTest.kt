package com.math_quiz.junpgle.com.math_quiz_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidEnergyPolicyTest {
    @Test
    fun `immediate poll is throttled inside the minimum interval`() {
        val lastEnqueuedAtMs = 1_000_000L

        assertFalse(
            AndroidEnergyPolicy.shouldEnqueueImmediateNotificationPoll(
                lastEnqueuedAtMs = lastEnqueuedAtMs,
                nowMs = lastEnqueuedAtMs +
                    AndroidEnergyPolicy.IMMEDIATE_NOTIFICATION_POLL_MIN_INTERVAL_MS - 1L,
                force = false
            )
        )
        assertTrue(
            AndroidEnergyPolicy.shouldEnqueueImmediateNotificationPoll(
                lastEnqueuedAtMs = lastEnqueuedAtMs,
                nowMs = lastEnqueuedAtMs +
                    AndroidEnergyPolicy.IMMEDIATE_NOTIFICATION_POLL_MIN_INTERVAL_MS,
                force = false
            )
        )
    }

    @Test
    fun `first forced and clock rollback polls are allowed`() {
        assertTrue(
            AndroidEnergyPolicy.shouldEnqueueImmediateNotificationPoll(
                lastEnqueuedAtMs = 0L,
                nowMs = 100L,
                force = false
            )
        )
        assertTrue(
            AndroidEnergyPolicy.shouldEnqueueImmediateNotificationPoll(
                lastEnqueuedAtMs = 100L,
                nowMs = 101L,
                force = true
            )
        )
        assertTrue(
            AndroidEnergyPolicy.shouldEnqueueImmediateNotificationPoll(
                lastEnqueuedAtMs = 100L,
                nowMs = 99L,
                force = false
            )
        )
    }

    @Test
    fun `high refresh is disabled for power saver or thermal pressure`() {
        assertTrue(
            AndroidEnergyPolicy.shouldRequestHighRefreshRate(
                isPowerSaveMode = false,
                isThermallyConstrained = false
            )
        )
        assertFalse(
            AndroidEnergyPolicy.shouldRequestHighRefreshRate(
                isPowerSaveMode = true,
                isThermallyConstrained = false
            )
        )
        assertFalse(
            AndroidEnergyPolicy.shouldRequestHighRefreshRate(
                isPowerSaveMode = false,
                isThermallyConstrained = true
            )
        )
    }

    @Test
    fun `unchanged full reminder schedules skip alarm registration churn`() {
        val reminders = "[{\"notifId\":30001,\"triggerAtMs\":20000}]"

        assertFalse(
            AndroidEnergyPolicy.shouldRescheduleReminderSchedule(
                existingJson = reminders,
                incomingJson = reminders,
                clearFirst = true,
                forceReschedule = false
            )
        )
        assertTrue(
            AndroidEnergyPolicy.shouldRescheduleReminderSchedule(
                existingJson = reminders,
                incomingJson = "[]",
                clearFirst = true,
                forceReschedule = false
            )
        )
    }

    @Test
    fun `forced and incremental reminder schedules still reschedule`() {
        val reminders = "[{\"notifId\":30001}]"

        assertTrue(
            AndroidEnergyPolicy.shouldRescheduleReminderSchedule(
                existingJson = reminders,
                incomingJson = reminders,
                clearFirst = true,
                forceReschedule = true
            )
        )
        assertTrue(
            AndroidEnergyPolicy.shouldRescheduleReminderSchedule(
                existingJson = reminders,
                incomingJson = reminders,
                clearFirst = false,
                forceReschedule = false
            )
        )
    }

    @Test
    fun `activity visibility follows Android lifecycle boundaries`() {
        AndroidAppVisibility.onActivityStopped()
        assertFalse(AndroidAppVisibility.isVisible)

        AndroidAppVisibility.onActivityStarted()
        assertTrue(AndroidAppVisibility.isVisible)

        AndroidAppVisibility.onActivityStopped()
        assertFalse(AndroidAppVisibility.isVisible)
    }

    @Test
    fun `running pomodoro uses a system countdown anchored at its end`() {
        val timer = AndroidEnergyPolicy.resolvePomodoroTimer(
            timerMode = "countdown",
            timerAnchorMs = 20_000L,
            isPaused = false,
            nowMs = 10_000L
        )

        assertEquals(20_000L, timer?.anchorTimeMs)
        assertTrue(timer?.countsDown == true)
    }

    @Test
    fun `running free focus uses a system count up anchored at its start`() {
        val timer = AndroidEnergyPolicy.resolvePomodoroTimer(
            timerMode = "countUp",
            timerAnchorMs = 10_000L,
            isPaused = false,
            nowMs = 20_000L
        )

        assertEquals(10_000L, timer?.anchorTimeMs)
        assertFalse(timer?.countsDown ?: true)
    }

    @Test
    fun `paused expired and invalid pomodoro timers stay static`() {
        assertNull(
            AndroidEnergyPolicy.resolvePomodoroTimer(
                timerMode = "countdown",
                timerAnchorMs = 20_000L,
                isPaused = true,
                nowMs = 10_000L
            )
        )
        assertNull(
            AndroidEnergyPolicy.resolvePomodoroTimer(
                timerMode = "countdown",
                timerAnchorMs = 10_000L,
                isPaused = false,
                nowMs = 20_000L
            )
        )
        assertNull(
            AndroidEnergyPolicy.resolvePomodoroTimer(
                timerMode = "unknown",
                timerAnchorMs = 10_000L,
                isPaused = false,
                nowMs = 20_000L
            )
        )
    }
}
