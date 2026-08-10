package com.math_quiz.junpgle.com.math_quiz_app.minors

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.plugin.common.MethodChannel

/**
 * Optional bridge for OEM parental-credential activities.
 *
 * Android has no single public parental-credential authentication API. These
 * actions are intentionally resolved before use, so unsupported ROMs simply
 * report false and never receive an implicit startActivity call.
 */
class ParentAuthManager(private val activity: Activity) {
    companion object {
        private const val REQUEST_CODE = 47031
        private val AUTHENTICATION_ACTIONS = listOf(
            "android.intent.action.PARENTAL_CONTROLS_AUTHENTICATE",
            "android.settings.PARENTAL_CONTROLS_AUTHENTICATE",
        )
    }

    private var pendingResult: MethodChannel.Result? = null

    fun isSupported(): Boolean = findAuthenticationIntent() != null

    fun requestAuthentication(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.success(false)
            return
        }

        val intent = findAuthenticationIntent()
        if (intent == null) {
            result.success(false)
            return
        }

        pendingResult = result
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (_: RuntimeException) {
            pendingResult = null
            result.success(false)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingResult
        pendingResult = null
        result?.success(resultCode == Activity.RESULT_OK)
        return true
    }

    fun dispose() {
        pendingResult?.success(false)
        pendingResult = null
    }

    private fun findAuthenticationIntent(): Intent? {
        val packageManager = activity.packageManager
        return AUTHENTICATION_ACTIONS
            .asSequence()
            .map { Intent(it) }
            .mapNotNull { intent ->
                val resolved = packageManager.resolveActivity(
                    intent,
                    PackageManager.MATCH_DEFAULT_ONLY,
                )
                if (resolved != null) intent else null
            }
            .firstOrNull()
    }
}
