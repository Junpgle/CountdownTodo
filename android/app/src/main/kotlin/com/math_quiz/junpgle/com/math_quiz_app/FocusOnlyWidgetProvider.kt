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

class FocusOnlyWidgetProvider : HomeWidgetProvider() {

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), prefs)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val appWidgetIds = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
            ?: appWidgetManager.getAppWidgetIds(ComponentName(context, FocusOnlyWidgetProvider::class.java))

        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE || intent.action == "es.antonborri.home_widget.action.UPDATE") {
            if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                onUpdate(context, appWidgetManager, appWidgetIds, prefs)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.list_timelogs)
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val titleColor = context.getColor(R.color.widget_text_primary)
        val bgColor = context.getColor(R.color.widget_bg)
        val widgetMode = widgetData.getString("widget_mode", "todo") ?: "todo"

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_focus_only)

            val bgImageId = context.resources.getIdentifier("widget_bg_image", "id", context.packageName)
            if (bgImageId != 0) {
                views.setInt(bgImageId, "setColorFilter", bgColor)
            }

            views.setTextColor(R.id.widget_title, titleColor)

            // 专注状态栏处理
            val focusActiveLayoutId = context.resources.getIdentifier("focus_active_layout", "id", context.packageName)
            if (focusActiveLayoutId != 0) {
                if (widgetMode == "focus") {
                    views.setViewVisibility(focusActiveLayoutId, View.VISIBLE)
                    views.setTextViewText(R.id.focus_title, widgetData.getString("focus_title", "专注中"))
                    views.setTextViewText(R.id.focus_timer, widgetData.getString("focus_timer", ""))
                    val tagsList = mutableListOf<String>()
                    for (i in 1..8) {
                        val tag = widgetData.getString("focus_tag_$i", "")
                        if (!tag.isNullOrEmpty()) tagsList.add(tag)
                    }
                    views.setTextViewText(R.id.focus_tags, tagsList.joinToString(" • "))
                    views.setViewVisibility(R.id.focus_tags, if (tagsList.isEmpty()) View.GONE else View.VISIBLE)
                } else {
                    views.setViewVisibility(focusActiveLayoutId, View.GONE)
                }
            }
            views.setTextViewText(R.id.tl_total, widgetData.getString("tl_total", "今日专注: 0 分钟"))

            val serviceIntent = Intent(context, FocusOnlyWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.list_timelogs, serviceIntent)
            views.setEmptyView(R.id.list_timelogs, R.id.empty_timelogs)

            val appIntent = Intent(context, MainActivity::class.java)
            val appPendingIntent = PendingIntent.getActivity(context, 0, appIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
            views.setPendingIntentTemplate(R.id.list_timelogs, appPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, 0, appIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
