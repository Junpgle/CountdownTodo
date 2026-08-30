package com.math_quiz.junpgle.com.math_quiz_app

import android.content.Context
import android.content.Intent
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
            val visibleUntilMs =
                (prefs.all["todo_${i}_visible_until"] as? Number)?.toLong() ?: 0L
            val isVisible =
                visibleUntilMs <= 0L || System.currentTimeMillis() < visibleUntilMs
            if (!title.isNullOrEmpty() && isVisible) {
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
        val views = RemoteViews(context.packageName, R.layout.widget_item_todo)
        val isDone = data.getBoolean("isDone")
        val title = data.getString("title", "")

        views.setCharSequence(R.id.todo_text, "setText", getHtmlSpanned(if (isDone) "<s>$title</s>" else title))
        WidgetProviderSupport.setTextColor(
            context,
            views,
            R.id.todo_text,
            if (isDone) R.color.widget_text_secondary else R.color.widget_text_primary
        )

        val dueText = data.getString("due", "")
        if (dueText.isNotEmpty() && !isDone) {
            views.setViewVisibility(R.id.todo_due, View.VISIBLE)
            views.setTextViewText(R.id.todo_due, dueText)
            val dueColor = when {
                dueText.contains("逾期") -> R.color.widget_due_overdue
                dueText.contains("今天") -> R.color.widget_due_today
                else -> R.color.widget_due_future
            }
            WidgetProviderSupport.setTextColor(context, views, R.id.todo_due, dueColor)
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
