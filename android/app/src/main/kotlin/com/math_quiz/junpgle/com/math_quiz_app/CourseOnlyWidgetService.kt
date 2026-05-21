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

class CourseOnlyWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return CourseOnlyRemoteViewsFactory(this.applicationContext, intent)
    }
}

class CourseOnlyRemoteViewsFactory(
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
            val name = prefs.getString("course_name_$i", "")
            if (!name.isNullOrEmpty()) {
                val bundle = Bundle()
                bundle.putString("name", name)
                bundle.putString("date", prefs.getString("course_date_$i", ""))
                bundle.putString("time", prefs.getString("course_time_$i", ""))
                bundle.putString("room", prefs.getString("course_room_$i", ""))
                bundle.putString("id", prefs.getString("course_id_$i", ""))
                itemsData.add(bundle)
            }
        }
    }

    override fun onDestroy() {
        itemsData.clear()
    }

    override fun getCount(): Int = itemsData.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position >= itemsData.size) return RemoteViews(context.packageName, R.layout.widget_item_course)

        val data = itemsData[position]
        val isDarkMode = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val primaryTextColor = context.getColor(R.color.widget_text_primary)
        val secondaryTextColor = context.getColor(R.color.widget_text_secondary)

        val views = RemoteViews(context.packageName, R.layout.widget_item_course)
        views.setCharSequence(R.id.course_date, "setText", getHtmlSpanned(data.getString("date", "")))
        views.setTextColor(R.id.course_date, secondaryTextColor)

        val cId = data.getString("id", "")
        val urgentCourseId = prefs.getString("urgent_course_id", "")
        val redColor = Color.parseColor(if (isDarkMode) "#F87171" else "#EF4444")

        views.setCharSequence(R.id.course_name, "setText", getHtmlSpanned(data.getString("name", "")))
        views.setTextColor(R.id.course_name, if (cId == urgentCourseId && urgentCourseId?.isNotEmpty() == true) redColor else primaryTextColor)

        views.setTextViewText(R.id.course_time, data.getString("time", ""))
        views.setTextColor(R.id.course_time, secondaryTextColor)

        views.setTextViewText(R.id.course_room, data.getString("room", ""))
        views.setTextColor(R.id.course_room, secondaryTextColor)

        views.setOnClickFillInIntent(R.id.course_name, Intent())
        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
