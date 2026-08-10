package com.math_quiz.junpgle.com.math_quiz_app.minors

data class GoogleAgeSignalsState(
    val available: Boolean,
    val status: String,
    val ageLower: Int? = null,
    val ageUpper: Int? = null,
    val ageBand: String = "unknown",
    val ageRangeSource: String? = null,
    val significantChangeStatus: String? = null,
    val significantChangeApprovalDateMillis: Long? = null,
    val lastError: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "available" to available,
        "status" to status,
        "ageLower" to ageLower,
        "ageUpper" to ageUpper,
        "ageBand" to ageBand,
        "ageRangeSource" to ageRangeSource,
        "significantChangeStatus" to significantChangeStatus,
        "significantChangeApprovalDateMillis" to significantChangeApprovalDateMillis,
        "lastError" to lastError,
    )
}
