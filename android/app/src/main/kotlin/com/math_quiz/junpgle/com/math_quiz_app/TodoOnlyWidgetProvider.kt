package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
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
            TodoOnlyWidgetProvider::class.java
        )

        if (intent.action == "MARK_TODO_DONE") {
            val todoId = intent.getStringExtra("todo_id")
            if (todoId != null) {
                val flutterIntent = Intent(context, es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java).apply {
                    data = android.net.Uri.parse("todowidget://markdone/$todoId")
                    action = "es.antonborri.home_widget.action.BACKGROUND"
                }
                context.sendBroadcast(flutterIntent)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.list_todos)
            }
        }

        if (WidgetProviderSupport.isUpdateAction(intent)) {
            if (appWidgetIds.isNotEmpty()) {
                onUpdate(context, appWidgetManager, appWidgetIds, prefs)
                WidgetProviderSupport.notifyListChanged(
                    appWidgetManager,
                    appWidgetIds,
                    R.id.list_todos
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
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_todo_only)
            WidgetProviderSupport.applyCommonChrome(context, views, R.id.widget_title)
            val serviceIntent = WidgetProviderSupport.serviceIntent(
                context,
                appWidgetId,
                TodoOnlyWidgetService::class.java
            )
            views.setRemoteAdapter(R.id.list_todos, serviceIntent)
            views.setEmptyView(R.id.list_todos, R.id.empty_todos)

            val appPendingIntent = WidgetProviderSupport.mainActivityPendingIntent(context)
            views.setOnClickPendingIntent(android.R.id.background, appPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
