package com.math_quiz.junpgle.com.math_quiz_app.minors

interface AndroidMinorModeAdapter {
    fun readState(): MinorModeState
    val observedSecureSettingKeys: List<String>
}
