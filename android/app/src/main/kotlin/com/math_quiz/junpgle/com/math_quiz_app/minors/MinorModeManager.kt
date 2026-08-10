package com.math_quiz.junpgle.com.math_quiz_app.minors

import android.app.Activity
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MinorModeManager(private val activity: Activity) {
    companion object {
        const val CHANNEL = "com.math_quiz_app/minor_mode"
        const val EVENT_CHANNEL = "com.math_quiz_app/minor_mode_events"
        private const val PARENTAL_CHILD_MANAGEMENT_ACTION =
            "com.android.action.PARENTAL_CHILD_MANAGEMENT"
        private const val PARENTAL_CONTROLS_SETTINGS_ACTION =
            "android.settings.PARENTAL_CONTROLS_SETTINGS"
    }

    private val adapter: AndroidMinorModeAdapter = ChinaMinorModeAdapter(activity)
    private val googleAgeSignalsAdapter = GoogleAgeSignalsAdapter(activity, activity)
    private val parentAuthManager = ParentAuthManager(activity)
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var observerRegistered = false

    private val contentObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            publishState()
        }
    }

    fun register(flutterEngine: FlutterEngine) {
        disposeChannels()

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result -> handleMethodCall(call, result) }
        }

        eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerObserverIfNeeded()
                    publishState()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }

        registerObserverIfNeeded()
    }

    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent? = null,
    ): Boolean = parentAuthManager.onActivityResult(requestCode, resultCode, data)

    fun dispose() {
        try {
            if (observerRegistered) {
                activity.contentResolver.unregisterContentObserver(contentObserver)
            }
        } catch (_: RuntimeException) {
            // Activity teardown can race with the observer lifecycle.
        }
        observerRegistered = false
        eventSink = null
        googleAgeSignalsAdapter.dispose()
        parentAuthManager.dispose()
        disposeChannels()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getMinorModeState", "refreshMinorModeState" -> {
                result.success(readState().toMap())
            }

            "isParentAuthenticationSupported" -> {
                result.success(parentAuthManager.isSupported())
            }

            "getGoogleAgeSignalsState" -> {
                result.success(googleAgeSignalsAdapter.getState().toMap())
            }

            "refreshGoogleAgeSignals" -> {
                googleAgeSignalsAdapter.refreshAgeSignals(result)
            }

            "requestGoogleAgeSignals" -> {
                googleAgeSignalsAdapter.requestAgeSignals(result)
            }

            "requestParentAuthentication" -> {
                parentAuthManager.requestAuthentication(result)
            }

            "openMinorModeSettings" -> {
                result.success(openMinorModeSettings())
            }

            else -> result.notImplemented()
        }
    }

    private fun readState(): MinorModeState {
        return try {
            adapter.readState().copy(
                parentAuthenticationSupported = parentAuthManager.isSupported(),
            )
        } catch (error: RuntimeException) {
            MinorModeState(
                systemSupported = false,
                systemEnabled = false,
                ageRange = null,
                source = "unsupported",
                parentAuthenticationSupported = false,
                systemStateReadFailed = true,
                lastError = error.toString(),
            )
        }
    }

    private fun publishState() {
        eventSink?.success(readState().toMap())
    }

    private fun registerObserverIfNeeded() {
        if (observerRegistered) return
        try {
            for (key in adapter.observedSecureSettingKeys) {
                activity.contentResolver.registerContentObserver(
                    Settings.Secure.getUriFor(key),
                    false,
                    contentObserver,
                )
            }
            observerRegistered = true
        } catch (_: SecurityException) {
            unregisterObserverAfterPartialRegistration()
            observerRegistered = false
        } catch (_: RuntimeException) {
            unregisterObserverAfterPartialRegistration()
            observerRegistered = false
        }
    }

    private fun unregisterObserverAfterPartialRegistration() {
        try {
            activity.contentResolver.unregisterContentObserver(contentObserver)
        } catch (_: RuntimeException) {
            // A failed/partial registration must not prevent Activity teardown.
        }
    }

    private fun openMinorModeSettings(): Boolean {
        val intent = listOf(
            PARENTAL_CHILD_MANAGEMENT_ACTION,
            PARENTAL_CONTROLS_SETTINGS_ACTION,
        ).asSequence()
            .map { action ->
                Intent(action).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            }
            .firstOrNull { candidate ->
                candidate.resolveActivity(activity.packageManager) != null
            }
            ?: Intent(Settings.ACTION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

        return try {
            activity.startActivity(intent)
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun disposeChannels() {
        eventSink = null
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
    }
}
