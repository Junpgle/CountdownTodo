package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
        val prefs = WidgetProviderSupport.preferences(context)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), prefs)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val prefs = WidgetProviderSupport.preferences(context)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val appWidgetIds = WidgetProviderSupport.widgetIds(
            context,
            intent,
            FocusOnlyWidgetProvider::class.java
        )

        if (WidgetProviderSupport.isUpdateAction(intent)) {
            if (appWidgetIds.isNotEmpty()) {
                onUpdate(context, appWidgetManager, appWidgetIds, prefs)
                WidgetProviderSupport.notifyListChanged(
                    appWidgetManager,
                    appWidgetIds,
                    R.id.list_timelogs
                )
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val widgetMode = widgetData.getString("widget_mode", "todo") ?: "todo"

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_focus_only)

            WidgetProviderSupport.applyCommonChrome(context, views, R.id.widget_title)

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

            val serviceIntent = WidgetProviderSupport.serviceIntent(
                context,
                appWidgetId,
                FocusOnlyWidgetService::class.java
            )
            views.setRemoteAdapter(R.id.list_timelogs, serviceIntent)
            views.setEmptyView(R.id.list_timelogs, R.id.empty_timelogs)

            val appPendingIntent = WidgetProviderSupport.mainActivityPendingIntent(
                context,
                mutable = true
            )
            views.setPendingIntentTemplate(R.id.list_timelogs, appPendingIntent)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                WidgetProviderSupport.mainActivityPendingIntent(context)
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
