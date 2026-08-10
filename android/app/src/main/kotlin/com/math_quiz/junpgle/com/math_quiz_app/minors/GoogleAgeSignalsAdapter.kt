package com.math_quiz.junpgle.com.math_quiz_app.minors

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import com.google.android.play.agesignals.AgeSignalsAccessRequest
import com.google.android.play.agesignals.AgeSignalsManager
import com.google.android.play.agesignals.AgeSignalsManagerFactory
import com.google.android.play.agesignals.AgeSignalsRequest
import com.google.android.play.agesignals.model.AgeSignalsStatus
import com.google.android.play.agesignals.model.AgeRangeSource
import com.google.android.play.agesignals.model.SignificantChangeStatus
import io.flutter.plugin.common.MethodChannel

/**
 * Optional adapter for the public Google Play Age Signals API.
 *
 * Age signals are deliberately opt-in. When a shared signal identifies a
 * minor, Flutter folds it into the local policy state; it never disables APK
 * updates or the manual mode. A sideloaded APK or a device without Play
 * support reports unavailable or an API error.
 */
class GoogleAgeSignalsAdapter(
    context: Context,
    private val activity: Activity,
) {
    companion object {
        const val STATUS_NOT_REQUESTED = "notRequested"
        const val STATUS_SHARED = "shared"
        const val STATUS_NOT_SHARED = "notShared"
        const val STATUS_VERIFICATION_REQUIRED = "verificationRequired"
        const val STATUS_UNAVAILABLE = "unavailable"
        const val STATUS_ERROR = "error"
        private const val PREFS_NAME = "minor_mode_age_signals"
        private const val PREF_STATUS = "status"
        private const val PREF_AGE_LOWER = "age_lower"
        private const val PREF_AGE_UPPER = "age_upper"
        private const val PREF_AGE_BAND = "age_band"
        private const val PREF_AGE_RANGE_SOURCE = "age_range_source"
        private const val PREF_SIGNIFICANT_CHANGE_STATUS = "significant_change_status"
        private const val PREF_SIGNIFICANT_CHANGE_APPROVAL_DATE =
            "significant_change_approval_date"
    }

    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val manager: AgeSignalsManager?
    private var pendingResult: MethodChannel.Result? = null
    private var disposed = false
    private var state = restoreState()

    init {
        manager = try {
            AgeSignalsManagerFactory.create(context.applicationContext)
        } catch (error: RuntimeException) {
            state = GoogleAgeSignalsState(
                available = false,
                status = STATUS_UNAVAILABLE,
                lastError = error.toString(),
            )
            null
        }
        if (manager != null && state.status == STATUS_UNAVAILABLE) {
            state = GoogleAgeSignalsState(
                available = true,
                status = STATUS_NOT_REQUESTED,
            )
        }
    }

    fun getState(): GoogleAgeSignalsState = state

    fun refreshAgeSignals(result: MethodChannel.Result) {
        if (disposed || manager == null || state.status != STATUS_SHARED) {
            result.success(state.toMap())
            return
        }
        if (pendingResult != null) {
            result.success(state.toMap())
            return
        }
        pendingResult = result
        checkAgeSignals(manager)
    }

    fun requestAgeSignals(result: MethodChannel.Result) {
        if (disposed) {
            result.success(state.toMap())
            return
        }
        if (pendingResult != null) {
            result.success(state.toMap())
            return
        }

        val ageSignalsManager = manager
        if (ageSignalsManager == null) {
            result.success(state.toMap())
            return
        }

        pendingResult = result
        try {
            val accessRequest = AgeSignalsAccessRequest.builder()
                .setActivity(activity)
                .build()
            ageSignalsManager.requestAgeSignalsAccess(accessRequest)
                .addOnSuccessListener { accessResult ->
                    when (accessResult.ageSignalsStatus()) {
                        AgeSignalsStatus.SHARED -> checkAgeSignals(ageSignalsManager)
                        AgeSignalsStatus.NOT_SHARED -> finish(
                            GoogleAgeSignalsState(
                                available = true,
                                status = STATUS_NOT_SHARED,
                            ),
                        )
                        AgeSignalsStatus.VERIFICATION_REQUIRED -> finish(
                            GoogleAgeSignalsState(
                                available = true,
                                status = STATUS_VERIFICATION_REQUIRED,
                            ),
                        )
                        else -> finishError("Unknown age signals status")
                    }
                }
                .addOnFailureListener { error -> finishError(error.toString()) }
        } catch (error: RuntimeException) {
            finishError(error.toString())
        }
    }

    fun dispose() {
        disposed = true
        pendingResult?.success(state.toMap())
        pendingResult = null
    }

    private fun checkAgeSignals(ageSignalsManager: AgeSignalsManager) {
        try {
            ageSignalsManager.checkAgeSignals(AgeSignalsRequest.builder().build())
                .addOnSuccessListener { result ->
                    finish(
                        stateFromResult(
                            result = result,
                        ),
                    )
                }
                .addOnFailureListener { error -> finishError(error.toString()) }
        } catch (error: RuntimeException) {
            finishError(error.toString())
        }
    }

    private fun stateFromResult(
        result: com.google.android.play.agesignals.AgeSignalsResult,
    ): GoogleAgeSignalsState {
        val ageLower = result.ageLower()
        val ageUpper = result.ageUpper()
        return GoogleAgeSignalsState(
            available = true,
            status = STATUS_SHARED,
            ageLower = ageLower,
            ageUpper = ageUpper,
            ageBand = mapAgeBand(ageLower, ageUpper),
            ageRangeSource = mapAgeRangeSource(result.ageRangeSource()),
            significantChangeStatus = mapSignificantChangeStatus(
                result.significantChangeStatus(),
            ),
            significantChangeApprovalDateMillis =
                result.significantChangeApprovalDate()?.time,
        )
    }

    private fun finish(nextState: GoogleAgeSignalsState) {
        if (disposed) return
        state = nextState
        persistState(state)
        val result = pendingResult ?: return
        pendingResult = null
        result.success(state.toMap())
    }

    private fun finishError(message: String) {
        if (state.status == STATUS_SHARED) {
            finish(
                state.copy(
                    available = manager != null,
                    lastError = message,
                ),
            )
            return
        }
        finish(
            GoogleAgeSignalsState(
                available = manager != null,
                status = if (manager == null) STATUS_UNAVAILABLE else STATUS_ERROR,
                lastError = message,
            ),
        )
    }

    private fun restoreState(): GoogleAgeSignalsState {
        val storedStatus = preferences.getString(PREF_STATUS, null)
            ?: return GoogleAgeSignalsState(
                available = false,
                status = STATUS_UNAVAILABLE,
            )
        return GoogleAgeSignalsState(
            available = true,
            status = storedStatus,
            ageLower = if (preferences.contains(PREF_AGE_LOWER)) {
                preferences.getInt(PREF_AGE_LOWER, 0)
            } else {
                null
            },
            ageUpper = if (preferences.contains(PREF_AGE_UPPER)) {
                preferences.getInt(PREF_AGE_UPPER, 0)
            } else {
                null
            },
            ageBand = preferences.getString(PREF_AGE_BAND, "unknown") ?: "unknown",
            ageRangeSource = preferences.getString(PREF_AGE_RANGE_SOURCE, null),
            significantChangeStatus =
                preferences.getString(PREF_SIGNIFICANT_CHANGE_STATUS, null),
            significantChangeApprovalDateMillis = if (
                preferences.contains(PREF_SIGNIFICANT_CHANGE_APPROVAL_DATE)
            ) {
                preferences.getLong(PREF_SIGNIFICANT_CHANGE_APPROVAL_DATE, 0L)
            } else {
                null
            },
        )
    }

    private fun persistState(nextState: GoogleAgeSignalsState) {
        preferences.edit()
            .putString(PREF_STATUS, nextState.status)
            .putString(PREF_AGE_BAND, nextState.ageBand)
            .apply {
                if (nextState.ageLower == null) remove(PREF_AGE_LOWER)
                else putInt(PREF_AGE_LOWER, nextState.ageLower)
                if (nextState.ageUpper == null) remove(PREF_AGE_UPPER)
                else putInt(PREF_AGE_UPPER, nextState.ageUpper)
                if (nextState.ageRangeSource == null) remove(PREF_AGE_RANGE_SOURCE)
                else putString(PREF_AGE_RANGE_SOURCE, nextState.ageRangeSource)
                if (nextState.significantChangeStatus == null) {
                    remove(PREF_SIGNIFICANT_CHANGE_STATUS)
                } else {
                    putString(
                        PREF_SIGNIFICANT_CHANGE_STATUS,
                        nextState.significantChangeStatus,
                    )
                }
                if (nextState.significantChangeApprovalDateMillis == null) {
                    remove(PREF_SIGNIFICANT_CHANGE_APPROVAL_DATE)
                } else {
                    putLong(
                        PREF_SIGNIFICANT_CHANGE_APPROVAL_DATE,
                        nextState.significantChangeApprovalDateMillis,
                    )
                }
            }
            .apply()
    }

    private fun mapAgeRangeSource(value: Int?): String? = when (value) {
        AgeRangeSource.TIER_A -> "tierA"
        AgeRangeSource.TIER_B -> "tierB"
        AgeRangeSource.TIER_C -> "tierC"
        AgeRangeSource.TIER_D -> "tierD"
        else -> null
    }

    private fun mapSignificantChangeStatus(value: Int?): String? = when (value) {
        SignificantChangeStatus.APPROVED -> "approved"
        SignificantChangeStatus.PENDING -> "pending"
        SignificantChangeStatus.DECLINED -> "declined"
        else -> null
    }

    private fun mapAgeBand(
        ageLower: Int?,
        ageUpper: Int?,
    ): String {
        if (ageLower == null) {
            return "unknown"
        }

        return when {
            ageUpper != null && ageLower <= 12 && ageUpper <= 12 -> "under13"
            ageUpper != null && ageLower == 13 && ageUpper <= 15 -> "age13to15"
            ageUpper != null && ageLower == 12 && ageUpper <= 15 -> "age12to15"
            ageUpper != null && ageLower >= 16 && ageUpper <= 17 -> "age16to17"
            ageLower >= 18 -> "adult"
            else -> "unknown"
        }
    }
}
