package com.math_quiz.junpgle.com.math_quiz_app.minors

import android.content.Context
import android.os.Build
import android.provider.Settings
import java.util.Locale

/**
 * Optional best-effort adapter for OEM Secure Settings contracts used by the
 * domestic Android minor-mode integration. Missing keys mean unsupported;
 * they are not treated as an error and never prevent the app from starting.
 */
class ChinaMinorModeAdapter(private val context: Context) : AndroidMinorModeAdapter {
    companion object {
        const val CAPABILITY_KEY = "minors_mode"
        const val ENABLED_KEY = "minors_mode_enabled"
        const val AGE_RANGE_KEY = "minors_mode_age_range"
    }

    private val vendor = listOf(Build.MANUFACTURER, Build.BRAND)
        .joinToString(" ")
        .lowercase(Locale.ROOT)

    /**
     * The public Android contract is intentionally checked first. The OEM
     * aliases are only capability probes: a missing key means unsupported and
     * no key is written by the app. This keeps the adapter safe on ROMs that
     * do not expose a documented integration surface.
     */
    private val enabledKeys = listOf(ENABLED_KEY) + vendorAliases(
        "minor_mode_enabled",
    )
    private val ageRangeKeys = listOf(AGE_RANGE_KEY) + vendorAliases(
        "minor_mode_age_range",
    ) + vendorAliases("minor_age_range")
    private val capabilityKeys = listOf(CAPABILITY_KEY) + vendorAliases(
        "minor_mode_supported",
    ) + vendorAliases("minor_mode_capable")

    override val observedSecureSettingKeys =
        (enabledKeys + ageRangeKeys + capabilityKeys).distinct()

    override fun readState(): MinorModeState {
        val capability = firstReadable(capabilityKeys)
        val enabled = firstReadable(enabledKeys)
        val ageRange = firstReadable(ageRangeKeys)

        // The capability flag is authoritative when present. Some ROMs expose
        // only the state or age key, so retain the compatibility fallback only
        // when the capability flag itself is unavailable.
        val supported = capability?.let { it == 1 }
            ?: (enabled != null || ageRange != null)
        return MinorModeState(
            systemSupported = supported,
            systemEnabled = supported && enabled == 1,
            ageRange = ageRange,
            source = if (supported) "chinaSystem" else "unsupported",
            parentAuthenticationSupported = false,
        )
    }

    private fun firstReadable(keys: List<String>): Int? {
        for (key in keys) {
            val value = readSecureInt(key)
            if (value != null) return value
        }
        return null
    }

    private fun vendorAliases(key: String): List<String> {
        val aliases = when {
            vendor.contains("xiaomi") || vendor.contains("redmi") ||
                vendor.contains("poco") || vendor.contains("miui") -> listOf(
                "miui_$key",
                "xiaomi_$key",
            )
            vendor.contains("huawei") || vendor.contains("honor") -> listOf(
                "huawei_$key",
                "honor_$key",
            )
            vendor.contains("oppo") || vendor.contains("realme") ||
                vendor.contains("oneplus") || vendor.contains("coloros") -> listOf(
                "oppo_$key",
                "coloros_$key",
                "realme_$key",
            )
            vendor.contains("vivo") || vendor.contains("iqoo") ||
                vendor.contains("originos") -> listOf(
                "vivo_$key",
                "originos_$key",
            )
            else -> emptyList()
        }
        return aliases
    }

    private fun readSecureInt(key: String): Int? {
        return try {
            val value = Settings.Secure.getString(context.contentResolver, key)
                ?: return null
            when (value.trim().lowercase()) {
                "true" -> 1
                "false" -> 0
                else -> value.trim().toIntOrNull()
            }
        } catch (_: SecurityException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }
}
