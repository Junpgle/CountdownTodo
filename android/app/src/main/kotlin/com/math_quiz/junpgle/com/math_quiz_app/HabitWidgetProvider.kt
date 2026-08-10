package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class HabitWidgetProvider : HomeWidgetProvider() {

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
            HabitWidgetProvider::class.java
        )

        if (intent.action == "QUICK_CHECKIN") {
            val habitId = intent.getStringExtra("habit_id")
            if (habitId != null) {
                val value = intent.getStringExtra("habit_value") ?: ""
                val uri = Uri.parse(
                    if (value.isEmpty()) {
                        "todowidget://habitcheckin/$habitId"
                    } else {
                        "todowidget://habitcheckin/$habitId?value=$value"
                    }
                )
                val flutterIntent = Intent(
                    context,
                    es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java
                ).apply {
                    data = uri
                    action = "es.antonborri.home_widget.action.BACKGROUND"
                }
                context.sendBroadcast(flutterIntent)
                WidgetProviderSupport.notifyListChanged(
                    appWidgetManager,
                    appWidgetIds,
                    R.id.list_habits
                )
            }
        }

        if (WidgetProviderSupport.isUpdateAction(intent)) {
            if (appWidgetIds.isNotEmpty()) {
                onUpdate(context, appWidgetManager, appWidgetIds, prefs)
                WidgetProviderSupport.notifyListChanged(
                    appWidgetManager,
                    appWidgetIds,
                    R.id.list_habits
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
            val views = RemoteViews(context.packageName, R.layout.widget_habit)
            WidgetProviderSupport.applyCommonChrome(context, views, R.id.widget_title)
            val serviceIntent = WidgetProviderSupport.serviceIntent(
                context,
                appWidgetId,
                HabitWidgetService::class.java
            )
            views.setRemoteAdapter(R.id.list_habits, serviceIntent)
            views.setEmptyView(R.id.list_habits, R.id.empty_habits)

            // 第一阶段：点击打开应用（习惯中心入口）
            val appPendingIntent = WidgetProviderSupport.mainActivityPendingIntent(context)
            views.setOnClickPendingIntent(R.id.widget_root, appPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
