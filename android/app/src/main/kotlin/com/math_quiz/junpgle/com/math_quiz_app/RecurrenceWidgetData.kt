package com.math_quiz.junpgle.com.math_quiz_app

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

internal data class RecurrenceWidgetOccurrence(
    val occurrenceId: String,
    val startAtMs: Long,
    val dueAtMs: Long?,
    val isDone: Boolean,
    val isDateOnly: Boolean,
    val isProjected: Boolean
)

internal data class RecurrenceWidgetSeries(
    val seriesId: String,
    val title: String,
    val recurrenceText: String,
    val contextText: String?,
    val isActive: Boolean,
    val completedCount: Int,
    val overdueCount: Int,
    val totalCount: Int?,
    val occurrences: List<RecurrenceWidgetOccurrence>
)

internal enum class RecurrenceWidgetOccurrenceState {
    COMPLETED,
    OVERDUE,
    CURRENT,
    FUTURE
}

internal data class RecurrenceWidgetTimelineItem(
    val label: String,
    val symbol: String,
    val state: RecurrenceWidgetOccurrenceState,
    val isSelected: Boolean
)

internal data class RecurrenceWidgetPresentation(
    val title: String,
    val recurrenceText: String,
    val statusText: String,
    val scheduleText: String,
    val summaryText: String,
    val contextText: String?,
    val state: RecurrenceWidgetOccurrenceState,
    val timeline: List<RecurrenceWidgetTimelineItem>
)

internal object RecurrenceWidgetData {
    const val HOME_WIDGET_PREFERENCES = "HomeWidgetPreferences"

    private const val RECURRENCE_SERIES_KEY = "recurrence_series_json"
    private const val SELECTION_PREFERENCES = "RecurrenceWidgetPreferences"
    private const val SELECTION_KEY_PREFIX = "selected_series_"

    fun readSeries(widgetData: SharedPreferences): List<RecurrenceWidgetSeries> {
        val rawJson = widgetData.getString(RECURRENCE_SERIES_KEY, null)
            ?.takeIf { it.isNotBlank() }
            ?: return emptyList()

        return runCatching {
            val root = JSONArray(rawJson)
            buildList {
                for (index in 0 until root.length()) {
                    val item = root.optJSONObject(index) ?: continue
                    parseSeries(item)?.let(::add)
                }
            }.sortedWith(
                compareByDescending<RecurrenceWidgetSeries> { it.isActive }
                    .thenBy { nextOccurrenceMs(it) }
                    .thenBy { it.title }
            )
        }.getOrDefault(emptyList())
    }

    fun selectedSeriesId(context: Context, appWidgetId: Int): String? {
        return selectionPreferences(context)
            .getString("$SELECTION_KEY_PREFIX$appWidgetId", null)
            ?.takeIf { it.isNotBlank() }
    }

    fun saveSelectedSeriesId(context: Context, appWidgetId: Int, seriesId: String) {
        selectionPreferences(context)
            .edit()
            .putString("$SELECTION_KEY_PREFIX$appWidgetId", seriesId)
            .apply()
    }

    fun clearSelections(context: Context, appWidgetIds: IntArray) {
        val editor = selectionPreferences(context).edit()
        appWidgetIds.forEach { appWidgetId ->
            editor.remove("$SELECTION_KEY_PREFIX$appWidgetId")
        }
        editor.apply()
    }

    fun buildPresentation(
        series: RecurrenceWidgetSeries,
        nowMs: Long = System.currentTimeMillis()
    ): RecurrenceWidgetPresentation {
        val occurrences = distinctOccurrencesByDay(series.occurrences)
        val selected = selectOccurrence(occurrences, nowMs)
        val selectedState = selected?.let { occurrenceState(it, nowMs) }
            ?: RecurrenceWidgetOccurrenceState.FUTURE

        val scheduleOccurrence = if (selected?.isDone == true) {
            occurrences.firstOrNull {
                it.startAtMs > selected.startAtMs && !it.isDone
            } ?: selected
        } else {
            selected
        }
        val schedulePrefix = if (selected?.isDone == true && scheduleOccurrence !== selected) {
            "下一期 "
        } else {
            ""
        }

        val statusText = when (selectedState) {
            RecurrenceWidgetOccurrenceState.COMPLETED -> "本期已完成"
            RecurrenceWidgetOccurrenceState.OVERDUE -> "本期已逾期"
            RecurrenceWidgetOccurrenceState.CURRENT -> "本期进行中"
            RecurrenceWidgetOccurrenceState.FUTURE -> "下期待办"
        }

        val summaryTotal = series.totalCount?.takeIf { it > 0 }
            ?.let { "/${it}" }
            .orEmpty()
        val activeSuffix = if (series.isActive) "" else " · 循环已结束"

        return RecurrenceWidgetPresentation(
            title = series.title,
            recurrenceText = series.recurrenceText,
            statusText = statusText,
            scheduleText = schedulePrefix + formatSchedule(scheduleOccurrence, nowMs),
            summaryText = "已完成 ${series.completedCount}$summaryTotal 期 · 逾期 ${series.overdueCount} 期$activeSuffix",
            contextText = series.contextText?.takeIf { it.isNotBlank() },
            state = selectedState,
            timeline = buildTimeline(occurrences, selected, nowMs)
        )
    }

    private fun selectionPreferences(context: Context): SharedPreferences {
        return context.getSharedPreferences(SELECTION_PREFERENCES, Context.MODE_PRIVATE)
    }

    private fun parseSeries(json: JSONObject): RecurrenceWidgetSeries? {
        val seriesId = json.optString("seriesId").trim()
        if (seriesId.isEmpty()) return null

        val occurrencesJson = json.optJSONArray("occurrences") ?: JSONArray()
        val occurrences = buildList {
            for (index in 0 until occurrencesJson.length()) {
                val occurrence = occurrencesJson.optJSONObject(index) ?: continue
                val startAtMs = occurrence.optLong("startAtMs", 0L)
                if (startAtMs <= 0L) continue
                add(
                    RecurrenceWidgetOccurrence(
                        occurrenceId = occurrence.optString("occurrenceId"),
                        startAtMs = startAtMs,
                        dueAtMs = occurrence.nullableLong("dueAtMs"),
                        isDone = occurrence.optBoolean("isDone", false),
                        isDateOnly = occurrence.optBoolean("isDateOnly", false),
                        isProjected = occurrence.optBoolean("isProjected", false)
                    )
                )
            }
        }.sortedBy { it.startAtMs }

        return RecurrenceWidgetSeries(
            seriesId = seriesId,
            title = json.optString("title").ifBlank { "循环待办" },
            recurrenceText = json.optString("recurrenceText").ifBlank { "循环待办" },
            contextText = json.optString("contextText").trim().takeIf { it.isNotEmpty() },
            isActive = if (json.has("isActive")) json.optBoolean("isActive") else true,
            completedCount = json.optInt("completedCount", 0),
            overdueCount = json.optInt("overdueCount", 0),
            totalCount = json.nullableInt("totalCount"),
            occurrences = occurrences
        )
    }

    private fun JSONObject.nullableLong(key: String): Long? {
        return if (!has(key) || isNull(key)) null else optLong(key)
    }

    private fun JSONObject.nullableInt(key: String): Int? {
        return if (!has(key) || isNull(key)) null else optInt(key)
    }

    private fun nextOccurrenceMs(series: RecurrenceWidgetSeries): Long {
        val now = System.currentTimeMillis()
        return series.occurrences.firstOrNull { it.startAtMs >= now }?.startAtMs
            ?: Long.MAX_VALUE
    }

    private fun distinctOccurrencesByDay(
        occurrences: List<RecurrenceWidgetOccurrence>
    ): List<RecurrenceWidgetOccurrence> {
        val byDay = linkedMapOf<Long, RecurrenceWidgetOccurrence>()
        occurrences.sortedBy { it.startAtMs }.forEach { occurrence ->
            val day = startOfDay(occurrence.startAtMs)
            val previous = byDay[day]
            if (previous == null || (previous.isProjected && !occurrence.isProjected)) {
                byDay[day] = occurrence
            }
        }
        return byDay.values.sortedBy { it.startAtMs }
    }

    private fun selectOccurrence(
        occurrences: List<RecurrenceWidgetOccurrence>,
        nowMs: Long
    ): RecurrenceWidgetOccurrence? {
        if (occurrences.isEmpty()) return null
        val today = startOfDay(nowMs)

        occurrences.firstOrNull { startOfDay(it.startAtMs) == today }?.let { return it }

        val recentCutoff = Calendar.getInstance().apply {
            timeInMillis = today
            add(Calendar.DAY_OF_MONTH, -2)
        }.timeInMillis
        occurrences.lastOrNull {
            !it.isDone && startOfDay(it.startAtMs) in recentCutoff until today
        }?.let { return it }

        return occurrences.firstOrNull { startOfDay(it.startAtMs) > today }
            ?: occurrences.last()
    }

    private fun occurrenceState(
        occurrence: RecurrenceWidgetOccurrence,
        nowMs: Long
    ): RecurrenceWidgetOccurrenceState {
        if (occurrence.isDone) return RecurrenceWidgetOccurrenceState.COMPLETED

        val today = startOfDay(nowMs)
        val occurrenceDay = startOfDay(occurrence.startAtMs)
        if (occurrenceDay > today) return RecurrenceWidgetOccurrenceState.FUTURE

        val effectiveDue = occurrence.dueAtMs ?: Calendar.getInstance().apply {
            timeInMillis = occurrenceDay
            add(Calendar.DAY_OF_MONTH, 1)
        }.timeInMillis
        return if (effectiveDue <= nowMs) {
            RecurrenceWidgetOccurrenceState.OVERDUE
        } else {
            RecurrenceWidgetOccurrenceState.CURRENT
        }
    }

    private fun formatSchedule(
        occurrence: RecurrenceWidgetOccurrence?,
        nowMs: Long
    ): String {
        occurrence ?: return "暂无排期"
        val targetMs = occurrence.dueAtMs ?: occurrence.startAtMs
        val dayText = relativeDay(targetMs, nowMs)
        if (occurrence.isDateOnly) return "${dayText}内完成"

        val timeText = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(targetMs))
        return "$dayText $timeText"
    }

    private fun relativeDay(targetMs: Long, nowMs: Long): String {
        val targetDay = startOfDay(targetMs)
        val today = startOfDay(nowMs)
        if (targetDay == today) return "今天"

        val tomorrow = Calendar.getInstance().apply {
            timeInMillis = today
            add(Calendar.DAY_OF_MONTH, 1)
        }.timeInMillis
        if (targetDay == tomorrow) return "明天"

        val yesterday = Calendar.getInstance().apply {
            timeInMillis = today
            add(Calendar.DAY_OF_MONTH, -1)
        }.timeInMillis
        if (targetDay == yesterday) return "昨天"

        return SimpleDateFormat("M/d", Locale.getDefault()).format(Date(targetMs))
    }

    private fun buildTimeline(
        occurrences: List<RecurrenceWidgetOccurrence>,
        selected: RecurrenceWidgetOccurrence?,
        nowMs: Long
    ): List<RecurrenceWidgetTimelineItem> {
        if (occurrences.isEmpty() || selected == null) return emptyList()
        val selectedIndex = occurrences.indexOf(selected).coerceAtLeast(0)
        val startIndex = (selectedIndex - 3)
            .coerceAtLeast(0)
            .coerceAtMost((occurrences.size - 7).coerceAtLeast(0))

        return occurrences.drop(startIndex).take(7).map { occurrence ->
            val state = occurrenceState(occurrence, nowMs)
            RecurrenceWidgetTimelineItem(
                label = if (startOfDay(occurrence.startAtMs) == startOfDay(nowMs)) {
                    "今天"
                } else {
                    SimpleDateFormat("M/d", Locale.getDefault())
                        .format(Date(occurrence.startAtMs))
                },
                symbol = when (state) {
                    RecurrenceWidgetOccurrenceState.COMPLETED -> "✓"
                    RecurrenceWidgetOccurrenceState.OVERDUE -> "!"
                    RecurrenceWidgetOccurrenceState.CURRENT -> "●"
                    RecurrenceWidgetOccurrenceState.FUTURE -> "○"
                },
                state = state,
                isSelected = occurrence === selected
            )
        }
    }

    private fun startOfDay(timeMs: Long): Long {
        return Calendar.getInstance().apply {
            timeInMillis = timeMs
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }
}
