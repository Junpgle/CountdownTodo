package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class RecurrenceWidgetProvider : HomeWidgetProvider() {

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val widgetData = context.getSharedPreferences(
            RecurrenceWidgetData.HOME_WIDGET_PREFERENCES,
            Context.MODE_PRIVATE
        )
        updateWidget(context, appWidgetManager, appWidgetId, widgetData)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (
            intent.action != AppWidgetManager.ACTION_APPWIDGET_UPDATE &&
            intent.action != HOME_WIDGET_UPDATE_ACTION
        ) {
            return
        }

        val appWidgetManager = AppWidgetManager.getInstance(context)
        val appWidgetIds = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
            ?: appWidgetManager.getAppWidgetIds(
                ComponentName(context, RecurrenceWidgetProvider::class.java)
            )
        if (appWidgetIds.isEmpty()) return

        val widgetData = context.getSharedPreferences(
            RecurrenceWidgetData.HOME_WIDGET_PREFERENCES,
            Context.MODE_PRIVATE
        )
        onUpdate(context, appWidgetManager, appWidgetIds, widgetData)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId, widgetData)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        RecurrenceWidgetData.clearSelections(context, appWidgetIds)
        super.onDeleted(context, appWidgetIds)
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_recurrence)
        val seriesCatalog = RecurrenceWidgetData.readSeries(widgetData)
        val selectedSeriesId = RecurrenceWidgetData.selectedSeriesId(context, appWidgetId)
        val selectedSeries = seriesCatalog.firstOrNull { it.seriesId == selectedSeriesId }
        val configureIntent = configurePendingIntent(context, appWidgetId)

        views.setInt(
            R.id.widget_bg_image,
            "setColorFilter",
            context.getColor(R.color.widget_bg)
        )
        views.setTextColor(R.id.widget_title, context.getColor(R.color.widget_text_primary))
        views.setTextColor(R.id.recurrence_configure, context.getColor(R.color.widget_text_accent))
        views.setOnClickPendingIntent(R.id.recurrence_configure, configureIntent)

        if (selectedSeries == null) {
            showEmptyState(
                context = context,
                views = views,
                hadSelection = !selectedSeriesId.isNullOrBlank(),
                hasCatalog = seriesCatalog.any { it.isActive }
            )
            views.setOnClickPendingIntent(R.id.widget_root, configureIntent)
        } else {
            showSeries(context, appWidgetManager, appWidgetId, views, selectedSeries)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                detailPendingIntent(context, appWidgetId, selectedSeries.seriesId)
            )
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun showEmptyState(
        context: Context,
        views: RemoteViews,
        hadSelection: Boolean,
        hasCatalog: Boolean
    ) {
        views.setViewVisibility(R.id.recurrence_content, View.GONE)
        views.setViewVisibility(R.id.recurrence_empty, View.VISIBLE)
        views.setViewVisibility(R.id.recurrence_pattern, View.GONE)

        val message = when {
            hadSelection -> context.getString(R.string.widget_recurrence_missing_selection)
            hasCatalog -> context.getString(R.string.widget_recurrence_select_prompt)
            else -> context.getString(R.string.widget_recurrence_no_data)
        }
        views.setTextViewText(R.id.recurrence_empty_message, message)
        views.setTextViewText(
            R.id.recurrence_empty_action,
            context.getString(R.string.widget_recurrence_tap_to_choose)
        )
        views.setTextColor(
            R.id.recurrence_empty_message,
            context.getColor(R.color.widget_text_secondary)
        )
        views.setTextColor(
            R.id.recurrence_empty_action,
            context.getColor(R.color.widget_text_accent)
        )
    }

    private fun showSeries(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        views: RemoteViews,
        series: RecurrenceWidgetSeries
    ) {
        val presentation = RecurrenceWidgetData.buildPresentation(series)
        views.setViewVisibility(R.id.recurrence_content, View.VISIBLE)
        views.setViewVisibility(R.id.recurrence_empty, View.GONE)
        views.setViewVisibility(R.id.recurrence_pattern, View.VISIBLE)

        views.setTextViewText(R.id.recurrence_pattern, presentation.recurrenceText)
        views.setTextViewText(R.id.recurrence_title, presentation.title)
        views.setTextViewText(R.id.recurrence_status, presentation.statusText)
        views.setTextViewText(R.id.recurrence_schedule, presentation.scheduleText)
        views.setTextViewText(R.id.recurrence_summary, presentation.summaryText)
        views.setTextColor(R.id.recurrence_pattern, context.getColor(R.color.widget_text_secondary))
        views.setTextColor(R.id.recurrence_title, context.getColor(R.color.widget_text_primary))
        views.setTextColor(R.id.recurrence_schedule, context.getColor(R.color.widget_text_secondary))
        views.setTextColor(R.id.recurrence_summary, context.getColor(R.color.widget_text_secondary))
        views.setTextColor(R.id.recurrence_status, stateColor(context, presentation.state))

        val contextText = presentation.contextText
        views.setViewVisibility(
            R.id.recurrence_context,
            if (contextText == null) View.GONE else View.VISIBLE
        )
        if (contextText != null) {
            views.setTextViewText(R.id.recurrence_context, contextText)
            views.setTextColor(
                R.id.recurrence_context,
                context.getColor(R.color.widget_text_secondary)
            )
        }

        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val showTimeline = presentation.timeline.isNotEmpty() && minWidth >= 220 && minHeight >= 135
        views.setViewVisibility(
            R.id.recurrence_timeline,
            if (showTimeline) View.VISIBLE else View.GONE
        )
        bindTimeline(context, views, presentation.timeline)
    }

    private fun bindTimeline(
        context: Context,
        views: RemoteViews,
        timeline: List<RecurrenceWidgetTimelineItem>
    ) {
        val nodeIds = intArrayOf(
            R.id.recurrence_node_1,
            R.id.recurrence_node_2,
            R.id.recurrence_node_3,
            R.id.recurrence_node_4,
            R.id.recurrence_node_5,
            R.id.recurrence_node_6,
            R.id.recurrence_node_7
        )

        nodeIds.forEachIndexed { index, viewId ->
            val item = timeline.getOrNull(index)
            views.setViewVisibility(viewId, if (item == null) View.GONE else View.VISIBLE)
            if (item != null) {
                val symbol = if (
                    item.isSelected && item.state == RecurrenceWidgetOccurrenceState.FUTURE
                ) {
                    "●"
                } else {
                    item.symbol
                }
                views.setTextViewText(viewId, "$symbol\n${item.label}")
                views.setTextColor(viewId, stateColor(context, item.state, item.isSelected))
            }
        }
    }

    private fun stateColor(
        context: Context,
        state: RecurrenceWidgetOccurrenceState,
        isSelected: Boolean = true
    ): Int {
        return when (state) {
            RecurrenceWidgetOccurrenceState.COMPLETED ->
                context.getColor(R.color.widget_recurrence_completed)
            RecurrenceWidgetOccurrenceState.OVERDUE ->
                context.getColor(R.color.widget_recurrence_overdue)
            RecurrenceWidgetOccurrenceState.CURRENT ->
                context.getColor(R.color.widget_text_accent)
            RecurrenceWidgetOccurrenceState.FUTURE -> context.getColor(
                if (isSelected) R.color.widget_text_accent else R.color.widget_text_secondary
            )
        }
    }

    private fun configurePendingIntent(context: Context, appWidgetId: Int): PendingIntent {
        val intent = Intent(context, RecurrenceWidgetConfigureActivity::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_CONFIGURE
            data = Uri.parse("countdowntodo://widget/recurrence/configure/$appWidgetId")
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        return PendingIntent.getActivity(
            context,
            appWidgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun detailPendingIntent(
        context: Context,
        appWidgetId: Int,
        seriesId: String
    ): PendingIntent {
        val deepLink = Uri.Builder()
            .scheme("countdowntodo")
            .authority("todo")
            .appendPath("recurrence")
            .appendQueryParameter("seriesId", seriesId)
            .build()
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = deepLink
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        }
        return PendingIntent.getActivity(
            context,
            appWidgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private companion object {
        const val HOME_WIDGET_UPDATE_ACTION = "es.antonborri.home_widget.action.UPDATE"
    }
}
