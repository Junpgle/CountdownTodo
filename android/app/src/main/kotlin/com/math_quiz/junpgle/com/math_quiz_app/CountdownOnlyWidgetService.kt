package com.math_quiz.junpgle.com.math_quiz_app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.text.Html
import android.text.Spanned
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class CountdownOnlyWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return CountdownOnlyRemoteViewsFactory(this.applicationContext, intent)
    }
}

class CountdownOnlyRemoteViewsFactory(
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
            val title = prefs.getString("cd_title_$i", "")
            if (!title.isNullOrEmpty()) {
                val bundle = Bundle()
                bundle.putString("title", title)
                bundle.putString("days", prefs.getString("cd_days_$i", ""))
                itemsData.add(bundle)
            }
        }
    }

    override fun onDestroy() {
        itemsData.clear()
    }

    override fun getCount(): Int = itemsData.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position >= itemsData.size) return RemoteViews(context.packageName, R.layout.widget_item_cd)

        val data = itemsData[position]
        val views = RemoteViews(context.packageName, R.layout.widget_item_cd)
        views.setCharSequence(R.id.cd_title, "setText", getHtmlSpanned(data.getString("title", "")))
        WidgetProviderSupport.setTextColor(
            context,
            views,
            R.id.cd_title,
            R.color.widget_text_primary
        )
        views.setTextViewText(R.id.cd_days, data.getString("days", ""))
        WidgetProviderSupport.setTextColor(
            context,
            views,
            R.id.cd_days,
            R.color.widget_text_accent
        )
        views.setOnClickFillInIntent(R.id.cd_title, Intent())
        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
