package com.math_quiz.junpgle.com.math_quiz_app

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.text.Html
import android.text.Spanned
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class FocusOnlyWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return FocusOnlyRemoteViewsFactory(this.applicationContext, intent)
    }
}

class FocusOnlyRemoteViewsFactory(
    private val context: Context,
    private val intent: Intent
) : RemoteViewsService.RemoteViewsFactory {

    private val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
    private val itemsData = mutableListOf<Bundle>()

    private fun getHtmlSpanned(text: String?): Spanned {
        val safeText = text ?: ""
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
            Html.fromHtml(safeText, Html.FROM_HTML_MODE_LEGACY)
        } else {
            @Suppress("DEPRECATION") Html.fromHtml(safeText)
        }
    }

    override fun onCreate() {}

    override fun onDataSetChanged() {
        itemsData.clear()
        for (i in 1..50) {
            val title = prefs.getString("tl_title_$i", "")
            if (!title.isNullOrEmpty()) {
                val bundle = Bundle()
                bundle.putString("title", title)
                bundle.putString("time", prefs.getString("tl_time_$i", ""))
                itemsData.add(bundle)
            }
        }
    }

    override fun onDestroy() {
        itemsData.clear()
    }

    override fun getCount(): Int = itemsData.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position >= itemsData.size) return RemoteViews(context.packageName, R.layout.widget_item_timelog)

        val data = itemsData[position]
        val isDarkMode = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val primaryTextColor = context.getColor(R.color.widget_text_primary)

        val views = RemoteViews(context.packageName, R.layout.widget_item_timelog)
        views.setCharSequence(R.id.tl_title, "setText", getHtmlSpanned(data.getString("title", "")))
        views.setTextColor(R.id.tl_title, primaryTextColor)
        views.setTextViewText(R.id.tl_time, data.getString("time", ""))
        val greenColor = Color.parseColor(if (isDarkMode) "#34D399" else "#10B981")
        views.setTextColor(R.id.tl_time, greenColor)
        views.setOnClickFillInIntent(R.id.tl_title, Intent())
        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
