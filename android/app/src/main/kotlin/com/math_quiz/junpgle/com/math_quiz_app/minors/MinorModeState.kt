package com.math_quiz.junpgle.com.math_quiz_app.minors

data class MinorModeState(
    val systemSupported: Boolean,
    val systemEnabled: Boolean,
    val ageRange: Int?,
    val source: String,
    val parentAuthenticationSupported: Boolean,
    val systemStateReadFailed: Boolean = false,
    val lastError: String? = null,
) {
    val ageBand: String
        get() = when (ageRange) {
            1 -> "under3"
            2 -> "age3to7"
            3 -> "age8to11"
            4 -> "age12to15"
            5 -> "age16to17"
            else -> "unknown"
        }

    fun toMap(): Map<String, Any?> = mapOf(
        "systemSupported" to systemSupported,
        "systemEnabled" to systemEnabled,
        "ageRange" to ageRange,
        "ageBand" to ageBand,
        "source" to source,
        "parentAuthenticationSupported" to parentAuthenticationSupported,
        "systemStateReadFailed" to systemStateReadFailed,
        "lastError" to lastError,
    )
}
