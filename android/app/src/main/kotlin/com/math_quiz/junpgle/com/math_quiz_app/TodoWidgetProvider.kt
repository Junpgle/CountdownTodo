package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.text.Html
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class TodoWidgetProvider : HomeWidgetProvider() {

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), prefs)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        if (intent.action == "MARK_TODO_DONE") {
            val todoId = intent.getStringExtra("todo_id")
            if (todoId != null) {
                val flutterIntent = Intent(context, es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java).apply {
                    data = android.net.Uri.parse("todowidget://markdone/$todoId")
                    action = "es.antonborri.home_widget.action.BACKGROUND"
                }
                context.sendBroadcast(flutterIntent)
            }
        }

        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE || intent.action == "es.antonborri.home_widget.action.UPDATE") {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(ComponentName(context, TodoWidgetProvider::class.java))
            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

            if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                onUpdate(context, appWidgetManager, appWidgetIds, prefs)
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
            val views = RemoteViews(context.packageName, R.layout.widget_todo)

            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

            // 重新计算可用槽位 (加入了更多的留白，所以所需高度微调)
            var dynamicMax = 8
            if (minHeight > 0) {
                dynamicMax = maxOf(1, (minHeight - 55) / 34)
            }
            val maxSlots = minOf(dynamicMax, 8)

            val appIntent = Intent(context, MainActivity::class.java)
            val appPendingIntent = PendingIntent.getActivity(
                context, 0, appIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, appPendingIntent)

            for (i in 1..8) {
                val layoutId = context.resources.getIdentifier("todo_layout_$i", "id", context.packageName)
                if (layoutId == 0) continue

                val textId = context.resources.getIdentifier("todo_text_$i", "id", context.packageName)
                val checkboxId = context.resources.getIdentifier("todo_checkbox_$i", "id", context.packageName)
                val dueId = context.resources.getIdentifier("todo_due_$i", "id", context.packageName)

                if (i > maxSlots) {
                    views.setViewVisibility(layoutId, View.GONE)
                    continue
                }

                val title = widgetData.getString("todo_$i", "")
                val isDone = widgetData.getBoolean("todo_${i}_done", false)
                val id = widgetData.getString("todo_${i}_id", "")
                val dueText = widgetData.getString("todo_${i}_due", "")

                if (!title.isNullOrEmpty()) {
                    views.setViewVisibility(layoutId, View.VISIBLE)

                    // 现代配色方案：文字更深沉，删除线颜色更柔和
                    if (isDone) {
                        val spanned = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                            Html.fromHtml("<s>$title</s>", Html.FROM_HTML_MODE_LEGACY)
                        } else {
                            @Suppress("DEPRECATION")
                            Html.fromHtml("<s>$title</s>")
                        }
                        views.setCharSequence(textId, "setText", spanned)
                        views.setTextColor(textId, android.graphics.Color.parseColor("#9CA3AF")) // 浅灰
                        views.setImageViewResource(checkboxId, R.drawable.widget_checkbox_checked)
                    } else {
                        views.setTextViewText(textId, title)
                        views.setTextColor(textId, android.graphics.Color.parseColor("#1F2937")) // 深灰黑
                        views.setImageViewResource(checkboxId, R.drawable.widget_checkbox_empty)
                    }

                    // 日期标签更精致的上色方案
                    if (!dueText.isNullOrEmpty() && !isDone) {
                        views.setViewVisibility(dueId, View.VISIBLE)
                        views.setTextViewText(dueId, dueText)

                        if (dueText.contains("逾期")) {
                            views.setTextColor(dueId, android.graphics.Color.parseColor("#EF4444")) // 红色
                        } else if (dueText.contains("今天")) {
                            views.setTextColor(dueId, android.graphics.Color.parseColor("#F59E0B")) // 橘黄
                        } else {
                            views.setTextColor(dueId, android.graphics.Color.parseColor("#10B981")) // 翠绿
                        }
                    } else {
                        views.setViewVisibility(dueId, View.GONE)
                    }

                    if (!id.isNullOrEmpty()) {
                        val clickIntent = Intent(context, TodoWidgetProvider::class.java).apply {
                            action = "MARK_TODO_DONE"
                            putExtra("todo_id", id)
                            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
                        }
                        val pendingIntent = PendingIntent.getBroadcast(
                            context, i * 100, clickIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        views.setOnClickPendingIntent(checkboxId, pendingIntent)
                    }
                } else {
                    if (i == 1) {
                        views.setViewVisibility(layoutId, View.VISIBLE)
                        views.setTextViewText(textId, "🎉 今天太棒了，没有待办！")
                        views.setTextColor(textId, android.graphics.Color.parseColor("#6B7280"))
                        views.setImageViewResource(checkboxId, 0) // 隐藏第一行的空选框
                        views.setViewVisibility(dueId, View.GONE)

                        val emptyIntent = Intent()
                        val emptyPI = PendingIntent.getBroadcast(context, 999, emptyIntent, PendingIntent.FLAG_IMMUTABLE)
                        views.setOnClickPendingIntent(checkboxId, emptyPI)
                    } else {
                        views.setViewVisibility(layoutId, View.GONE)
                    }
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}