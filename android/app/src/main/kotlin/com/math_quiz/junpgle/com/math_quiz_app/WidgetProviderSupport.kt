package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews

/** Shared lifecycle and RemoteViews helpers for the list-based widgets. */
object WidgetProviderSupport {
    const val HOME_WIDGET_UPDATE_ACTION = "es.antonborri.home_widget.action.UPDATE"
    private const val PREFERENCES_NAME = "HomeWidgetPreferences"

    fun preferences(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun widgetIds(
        context: Context,
        intent: Intent,
        providerClass: Class<*>
    ): IntArray {
        val manager = AppWidgetManager.getInstance(context)
        return intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
            ?: manager.getAppWidgetIds(ComponentName(context, providerClass))
    }

    fun isUpdateAction(intent: Intent): Boolean =
        intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE ||
            intent.action == HOME_WIDGET_UPDATE_ACTION

    fun applyCommonChrome(context: Context, views: RemoteViews, titleViewId: Int) {
        val bgImageId = context.resources.getIdentifier(
            "widget_bg_image",
            "id",
            context.packageName
        )
        if (bgImageId != 0) {
            views.setInt(
                bgImageId,
                "setColorFilter",
                context.getColor(R.color.widget_bg)
            )
        }
        views.setTextColor(titleViewId, context.getColor(R.color.widget_text_primary))
    }

    fun serviceIntent(
        context: Context,
        appWidgetId: Int,
        serviceClass: Class<*>,
        listType: Int? = null
    ): Intent = Intent(context, serviceClass).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        if (listType != null) putExtra("list_type", listType)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
    }

    fun mainActivityPendingIntent(
        context: Context,
        mutable: Boolean = false
    ): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (mutable) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            flags
        )
    }

    fun notifyListChanged(
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
        listViewId: Int
    ) {
        if (appWidgetIds.isNotEmpty()) {
            manager.notifyAppWidgetViewDataChanged(appWidgetIds, listViewId)
        }
    }
}
