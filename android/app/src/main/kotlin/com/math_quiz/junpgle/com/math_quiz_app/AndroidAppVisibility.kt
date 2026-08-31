package com.math_quiz.junpgle.com.math_quiz_app

/**
 * Process-local Activity visibility used by WorkManager jobs.
 *
 * CountdownTodo has a single Android Activity and its workers run in the same
 * process. A process-local flag avoids persisted lifecycle state becoming
 * stale if Android kills the app while it is in the background.
 */
internal object AndroidAppVisibility {
    @Volatile
    var isVisible: Boolean = false
        private set

    fun onActivityStarted() {
        isVisible = true
    }

    fun onActivityStopped() {
        isVisible = false
    }
}
