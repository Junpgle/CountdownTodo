package com.math_quiz.junpgle.com.math_quiz_app

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Android's system Battery Saver state to Flutter.
 *
 * The system broadcast is the single source of truth, so Flutter consumers can
 * react immediately without polling PowerManager or keeping their own timers.
 */
class AndroidPowerSaveModeManager(
    private val activity: Activity,
    private val onPowerSaveModeChanged: (Boolean) -> Unit = {},
) {
    companion object {
        const val CHANNEL = "com.math_quiz_app/power_save_mode"
        const val EVENT_CHANNEL = "com.math_quiz_app/power_save_mode_events"
    }

    private val powerManager =
        activity.getSystemService(Context.POWER_SERVICE) as PowerManager
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false
    private var lastPublishedState: Boolean? = null

    private val powerSaveModeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == PowerManager.ACTION_POWER_SAVE_MODE_CHANGED) {
                publishState(force = false)
            }
        }
    }

    fun register(flutterEngine: FlutterEngine) {
        disposeChannels()

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }
        }

        eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    publishState(force = true)
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }

        registerReceiverIfNeeded()
        publishState(force = true)
    }

    fun dispose() {
        if (receiverRegistered) {
            try {
                activity.unregisterReceiver(powerSaveModeReceiver)
            } catch (_: RuntimeException) {
                // Activity teardown can race with receiver unregistration.
            }
        }
        receiverRegistered = false
        lastPublishedState = null
        eventSink = null
        disposeChannels()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPowerSaveMode", "refreshPowerSaveMode" -> {
                val enabled = powerManager.isPowerSaveMode
                publishState(force = false)
                result.success(enabled)
            }

            else -> result.notImplemented()
        }
    }

    private fun publishState(force: Boolean) {
        val enabled = powerManager.isPowerSaveMode
        if (!force && lastPublishedState == enabled) return

        lastPublishedState = enabled
        onPowerSaveModeChanged(enabled)
        eventSink?.success(enabled)
    }

    private fun registerReceiverIfNeeded() {
        if (receiverRegistered) return
        val filter = IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(
                    powerSaveModeReceiver,
                    filter,
                    Context.RECEIVER_EXPORTED,
                )
            } else {
                @Suppress("DEPRECATION")
                activity.registerReceiver(powerSaveModeReceiver, filter)
            }
            receiverRegistered = true
        } catch (_: RuntimeException) {
            receiverRegistered = false
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
