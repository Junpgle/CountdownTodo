package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class CourseOnlyWidgetProvider : HomeWidgetProvider() {

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
            CourseOnlyWidgetProvider::class.java
        )

        if (WidgetProviderSupport.isUpdateAction(intent)) {
            if (appWidgetIds.isNotEmpty()) {
                onUpdate(context, appWidgetManager, appWidgetIds, prefs)
                WidgetProviderSupport.notifyListChanged(
                    appWidgetManager,
                    appWidgetIds,
                    R.id.list_courses
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
            val views = RemoteViews(context.packageName, R.layout.widget_course_only)
            WidgetProviderSupport.applyCommonChrome(context, views, R.id.widget_title)
            val serviceIntent = WidgetProviderSupport.serviceIntent(
                context,
                appWidgetId,
                CourseOnlyWidgetService::class.java
            )
            views.setRemoteAdapter(R.id.list_courses, serviceIntent)
            views.setEmptyView(R.id.list_courses, R.id.empty_courses)

            val appPendingIntent = WidgetProviderSupport.mainActivityPendingIntent(
                context,
                mutable = true
            )
            views.setPendingIntentTemplate(R.id.list_courses, appPendingIntent)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                WidgetProviderSupport.mainActivityPendingIntent(context)
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
