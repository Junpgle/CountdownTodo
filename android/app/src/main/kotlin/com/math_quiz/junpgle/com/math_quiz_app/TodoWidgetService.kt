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

class TodoWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TodoRemoteViewsFactory(this.applicationContext, intent)
    }
}

class TodoRemoteViewsFactory(
    private val context: Context,
    private val intent: Intent
) : RemoteViewsService.RemoteViewsFactory {

    private val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
    private val listType = intent.getIntExtra("list_type", 0) // 0: Todo, 1: Course, 2: CD, 3: Timelog
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
        // 最多抓取 50 条数据 (你可以改成 100)
        for (i in 1..50) {
            val bundle = Bundle()
            var hasData = false
            when (listType) {
                0 -> { // Todos
                    val title = prefs.getString("todo_$i", "")
                    if (!title.isNullOrEmpty()) {
                        bundle.putString("title", title)
                        bundle.putBoolean("isDone", prefs.getBoolean("todo_${i}_done", false))
                        bundle.putString("id", prefs.getString("todo_${i}_id", ""))
                        bundle.putString("due", prefs.getString("todo_${i}_due", ""))
                        hasData = true
                    }
                }
                1 -> { // Courses
                    val name = prefs.getString("course_name_$i", "")
                    if (!name.isNullOrEmpty()) {
                        bundle.putString("name", name)
                        bundle.putString("date", prefs.getString("course_date_$i", ""))
                        bundle.putString("time", prefs.getString("course_time_$i", ""))
                        bundle.putString("room", prefs.getString("course_room_$i", ""))
                        bundle.putString("id", prefs.getString("course_id_$i", ""))
                        hasData = true
                    }
                }
                2 -> { // Countdowns
                    val title = prefs.getString("cd_title_$i", "")
                    if (!title.isNullOrEmpty()) {
                        bundle.putString("title", title)
                        bundle.putString("days", prefs.getString("cd_days_$i", ""))
                        hasData = true
                    }
                }
                3 -> { // Timelogs / Tags
                    val title = prefs.getString("tl_title_$i", "")
                    if (!title.isNullOrEmpty()) {
                        bundle.putString("title", title)
                        bundle.putString("time", prefs.getString("tl_time_$i", ""))
                        hasData = true
                    }
                }
            }
            if (hasData) itemsData.add(bundle)
        }
    }

    override fun onDestroy() {
        itemsData.clear()
    }

    override fun getCount(): Int = itemsData.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position >= itemsData.size) return RemoteViews(context.packageName, R.layout.widget_item_todo)

        val data = itemsData[position]
        val isDarkMode = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val primaryTextColor = Color.parseColor(if (isDarkMode) "#F3F4F6" else "#1F2937")
        val secondaryTextColor = Color.parseColor(if (isDarkMode) "#9CA3AF" else "#6B7280")

        when (listType) {
            0 -> {
                val views = RemoteViews(context.packageName, R.layout.widget_item_todo)
                val isDone = data.getBoolean("isDone")
                val title = data.getString("title", "")

                views.setCharSequence(R.id.todo_text, "setText", getHtmlSpanned(if (isDone) "<s>$title</s>" else title))
                views.setTextColor(R.id.todo_text, if (isDone) secondaryTextColor else primaryTextColor)

                val checkedResId = context.resources.getIdentifier(if (isDone) "widget_checkbox_checked" else "widget_checkbox_empty", "drawable", context.packageName)
                if (checkedResId != 0) views.setImageViewResource(R.id.todo_checkbox, checkedResId)

                // 处理复选框的点击：通过 FillInIntent 发送
                val todoId = data.getString("id", "")
                if (todoId.isNotEmpty()) {
                    val fillInIntent = Intent().apply { putExtra("todo_id", todoId) }
                    views.setOnClickFillInIntent(R.id.todo_checkbox, fillInIntent)
                }

                val dueText = data.getString("due", "")
                if (dueText.isNotEmpty() && !isDone) {
                    views.setViewVisibility(R.id.todo_due, View.VISIBLE)
                    views.setTextViewText(R.id.todo_due, dueText)
                    val redColor = Color.parseColor(if (isDarkMode) "#F87171" else "#EF4444")
                    val yellowColor = Color.parseColor(if (isDarkMode) "#FBBF24" else "#F59E0B")
                    val greenColor = Color.parseColor(if (isDarkMode) "#34D399" else "#10B981")
                    if (dueText.contains("逾期")) views.setTextColor(R.id.todo_due, redColor)
                    else if (dueText.contains("今天")) views.setTextColor(R.id.todo_due, yellowColor)
                    else views.setTextColor(R.id.todo_due, greenColor)
                } else {
                    views.setViewVisibility(R.id.todo_due, View.GONE)
                }
                return views
            }
            1 -> {
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

                // 为了让整个列表都可以点回 App
                views.setOnClickFillInIntent(R.id.course_name, Intent())
                return views
            }
            2 -> {
                val views = RemoteViews(context.packageName, R.layout.widget_item_cd)
                views.setCharSequence(R.id.cd_title, "setText", getHtmlSpanned(data.getString("title", "")))
                views.setTextColor(R.id.cd_title, primaryTextColor)
                views.setTextViewText(R.id.cd_days, data.getString("days", ""))
                val blueColor = Color.parseColor(if (isDarkMode) "#60A5FA" else "#3B82F6")
                views.setTextColor(R.id.cd_days, blueColor)
                views.setOnClickFillInIntent(R.id.cd_title, Intent())
                return views
            }
            3 -> {
                val views = RemoteViews(context.packageName, R.layout.widget_item_timelog)
                views.setCharSequence(R.id.tl_title, "setText", getHtmlSpanned(data.getString("title", "")))
                views.setTextColor(R.id.tl_title, primaryTextColor)
                views.setTextViewText(R.id.tl_time, data.getString("time", ""))
                val greenColor = Color.parseColor(if (isDarkMode) "#34D399" else "#10B981")
                views.setTextColor(R.id.tl_time, greenColor)
                views.setOnClickFillInIntent(R.id.tl_title, Intent())
                return views
            }
        }
        return RemoteViews(context.packageName, R.layout.widget_item_todo)
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}