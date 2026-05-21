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

class TodoOnlyWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TodoOnlyRemoteViewsFactory(this.applicationContext, intent)
    }
}

class TodoOnlyRemoteViewsFactory(
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
            val title = prefs.getString("todo_$i", "")
            if (!title.isNullOrEmpty()) {
                val bundle = Bundle()
                bundle.putString("title", title)
                bundle.putBoolean("isDone", prefs.getBoolean("todo_${i}_done", false))
                bundle.putString("id", prefs.getString("todo_${i}_id", ""))
                bundle.putString("due", prefs.getString("todo_${i}_due", ""))
                itemsData.add(bundle)
            }
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
        val primaryTextColor = context.getColor(R.color.widget_text_primary)
        val secondaryTextColor = context.getColor(R.color.widget_text_secondary)

        val views = RemoteViews(context.packageName, R.layout.widget_item_todo)
        val isDone = data.getBoolean("isDone")
        val title = data.getString("title", "")

        views.setCharSequence(R.id.todo_text, "setText", getHtmlSpanned(if (isDone) "<s>$title</s>" else title))
        views.setTextColor(R.id.todo_text, if (isDone) secondaryTextColor else primaryTextColor)

        val checkedResId = context.resources.getIdentifier(if (isDone) "widget_checkbox_checked" else "widget_checkbox_empty", "drawable", context.packageName)
        if (checkedResId != 0) views.setImageViewResource(R.id.todo_checkbox, checkedResId)

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

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
