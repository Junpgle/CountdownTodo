package com.math_quiz.junpgle.com.math_quiz_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CountdownReminderStoreTest {
    @Test
    fun `buildKey prefers countdownId and falls back to notifId`() {
        assertEquals(
            "cd-123@2026-11-27",
            CountdownReminderStore.buildKey(" cd-123 ", 71005, " 2026-11-27 ")
        )
        assertEquals(
            "notif_70001@2026-11-27",
            CountdownReminderStore.buildKey(null, 70001, "2026-11-27")
        )
        assertEquals(
            "notif_70001@2026-11-27",
            CountdownReminderStore.buildKey("  ", 70001, "2026-11-27")
        )
    }

    @Test
    fun `shouldSuppressPosting blocks dismissed or externally cleared notifications`() {
        // Explicit dismissal or completion always suppresses re-posting.
        assertTrue(
            CountdownReminderStore.shouldSuppressPosting(
                isDismissed = true,
                isShown = false,
                isAnyTrackedNotifActive = false
            )
        )
        assertTrue(
            CountdownReminderStore.shouldSuppressPosting(
                isDismissed = true,
                isShown = true,
                isAnyTrackedNotifActive = true
            )
        )

        // Already shown today and no longer in notification shade -> user swiped it away.
        assertTrue(
            CountdownReminderStore.shouldSuppressPosting(
                isDismissed = false,
                isShown = true,
                isAnyTrackedNotifActive = false
            )
        )

        // Never shown today -> allow posting.
        assertFalse(
            CountdownReminderStore.shouldSuppressPosting(
                isDismissed = false,
                isShown = false,
                isAnyTrackedNotifActive = false
            )
        )

        // Shown today and still active in shade -> do not treat as dismissed.
        assertFalse(
            CountdownReminderStore.shouldSuppressPosting(
                isDismissed = false,
                isShown = true,
                isAnyTrackedNotifActive = true
            )
        )
    }

    @Test
    fun `pruneKeySet retains newest date keys`() {
        val pruned = CountdownReminderStore.pruneKeySet(
            keys = setOf("a@2026-11-01", "b@2026-11-27", "c@2026-11-12"),
            maxEntries = 2
        )

        assertEquals(setOf("b@2026-11-27", "c@2026-11-12"), pruned)
    }

    @Test
    fun `resolveCategoryStyle formats compact and spaced labels consistently`() {
        val liveBirthday = CountdownReminderStore.resolveCategoryStyle("birthday", compactLabel = false)
        val alarmBirthday = CountdownReminderStore.resolveCategoryStyle("birthday", compactLabel = true)

        assertEquals(liveBirthday.iconResId, alarmBirthday.iconResId)
        assertEquals(liveBirthday.color, alarmBirthday.color)
        assertEquals("🎂 生日", liveBirthday.label)
        assertEquals("🎂生日", alarmBirthday.label)
    }
}
