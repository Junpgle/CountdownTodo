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

class TodoOnlyWidgetProvider : HomeWidgetProvider() {

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
            ?: appWidgetManager.getAppWidgetIds(ComponentName(context, TodoOnlyWidgetProvider::class.java))

        if (intent.action == "MARK_TODO_DONE") {
            val todoId = intent.getStringExtra("todo_id")
            if (todoId != null) {
                val flutterIntent = Intent(context, es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java).apply {
                    data = Uri.parse("todowidget://markdone/$todoId")
                    action = "es.antonborri.home_widget.action.BACKGROUND"
                }
                context.sendBroadcast(flutterIntent)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.list_todos)
            }
        }

        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE || intent.action == "es.antonborri.home_widget.action.UPDATE") {
            if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                onUpdate(context, appWidgetManager, appWidgetIds, prefs)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.list_todos)
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

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_todo_only)

            val bgImageId = context.resources.getIdentifier("widget_bg_image", "id", context.packageName)
            if (bgImageId != 0) {
                views.setInt(bgImageId, "setColorFilter", bgColor)
            }

            views.setTextColor(R.id.widget_title, titleColor)

            val serviceIntent = Intent(context, TodoOnlyWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.list_todos, serviceIntent)
            views.setEmptyView(R.id.list_todos, R.id.empty_todos)

            val clickIntent = Intent(context, TodoOnlyWidgetProvider::class.java).apply {
                action = "MARK_TODO_DONE"
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
            }
            val clickPendingIntent = PendingIntent.getBroadcast(
                context, 0, clickIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            views.setPendingIntentTemplate(R.id.list_todos, clickPendingIntent)

            val appIntent = Intent(context, MainActivity::class.java)
            val appPendingIntent = PendingIntent.getActivity(context, 0, appIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_root, appPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
