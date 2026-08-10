package com.math_quiz.junpgle.com.math_quiz_app.minors

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.os.Messenger
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
        private const val ACTION_PARENTAL_CREDENTIAL_AUTHENTICATE =
            "com.android.action.PARENTAL_CREDENTIAL_AUTHENTICATE"
        private const val KEY_AUTHENTICATE_MESSAGE =
            "key_authentication_message"
        private const val KEY_AUTHENTICATE_TYPE = "key_authentication_type"
        private const val KEY_AUTHENTICATION_RESULT_CODE =
            "key_authentication_result_code"
        private const val KEY_AUTHENTICATION_MESSENGER =
            "key_authentication_messenger"
        private const val AUTHENTICATE_TYPE_ALL = 0x1 or 0x2 or 0x4 or 0x8
        private const val RESULT_SUCCEEDED = 100
        private val AUTHENTICATION_ACTIONS = listOf(
            ACTION_PARENTAL_CREDENTIAL_AUTHENTICATE,
            "android.intent.action.PARENTAL_CONTROLS_AUTHENTICATE",
            "android.settings.PARENTAL_CONTROLS_AUTHENTICATE",
        )
    }

    private var pendingResult: MethodChannel.Result? = null
    private val messenger = Messenger(
        Handler(Looper.getMainLooper()) { message ->
            handleAuthenticationMessage(message)
            true
        },
    )

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
            intent.putExtra(
                KEY_AUTHENTICATE_MESSAGE,
                "请验证家长身份后继续",
            )
            intent.putExtra(KEY_AUTHENTICATE_TYPE, AUTHENTICATE_TYPE_ALL)
            intent.putExtra(KEY_AUTHENTICATION_MESSENGER, messenger)
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (_: RuntimeException) {
            pendingResult = null
            result.success(false)
        }
    }

    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent? = null,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val messageResult = data?.getIntExtra(
            KEY_AUTHENTICATION_RESULT_CODE,
            Int.MIN_VALUE,
        ) ?: Int.MIN_VALUE
        val succeeded = messageResult == RESULT_SUCCEEDED ||
            (messageResult == Int.MIN_VALUE && resultCode == Activity.RESULT_OK)
        complete(succeeded)
        return true
    }

    fun dispose() {
        pendingResult?.success(false)
        pendingResult = null
    }

    private fun handleAuthenticationMessage(message: Message) {
        val resultCode = message.data?.getInt(
            KEY_AUTHENTICATION_RESULT_CODE,
            Int.MIN_VALUE,
        ) ?: Int.MIN_VALUE
        if (resultCode == Int.MIN_VALUE) return
        complete(resultCode == RESULT_SUCCEEDED)
    }

    private fun complete(succeeded: Boolean) {
        val result = pendingResult ?: return
        pendingResult = null
        result.success(succeeded)
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
