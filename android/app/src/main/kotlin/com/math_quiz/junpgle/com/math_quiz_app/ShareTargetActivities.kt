package com.math_quiz.junpgle.com.math_quiz_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * Small Android share-target proxies.
 *
 * receive_sharing_intent listens on MainActivity. These activities only add a
 * private MIME type that identifies the user's chosen purpose, then forward
 * the original stream/text/URI to MainActivity. This keeps the share sheet
 * entries separate without duplicating the Flutter engine or file handling.
 */
abstract class ShareTargetActivity : Activity() {
    protected abstract val targetMimeType: String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        forwardToMainActivity(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        forwardToMainActivity(intent)
    }

    private fun forwardToMainActivity(source: Intent) {
        val forwarded = Intent(this, MainActivity::class.java).apply {
            action = source.action
            data = source.data
            type = targetMimeType
            clipData = source.clipData
            putExtras(source)
            if (source.action == Intent.ACTION_SEND_MULTIPLE) {
                val streamCount = source.getParcelableArrayListExtra<Uri>(
                    Intent.EXTRA_STREAM,
                )?.size ?: source.clipData?.itemCount ?: 0
                if (streamCount > 0) {
                    putExtra(
                        Intent.EXTRA_MIME_TYPES,
                        Array(streamCount) { targetMimeType },
                    )
                }
            }
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(forwarded)
        finish()
    }
}

class CourseImportShareActivity : ShareTargetActivity() {
    override val targetMimeType = "application/vnd.countdowntodo.course"
}

class ImageRecognitionShareActivity : ShareTargetActivity() {
    override val targetMimeType = "application/vnd.countdowntodo.image"
}

class FinanceImportShareActivity : ShareTargetActivity() {
    override val targetMimeType = "application/vnd.countdowntodo.finance"
}
