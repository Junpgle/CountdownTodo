package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.text.Html
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class TodoWidgetProvider : HomeWidgetProvider() {

    // 原生接收广播
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // 拦截我们自定义的打勾事件
        if (intent.action == "MARK_TODO_DONE") {
            val todoId = intent.getStringExtra("todo_id")
            if (todoId != null) {
                // 1. 将数据透传给 Flutter 的 HomeWidgetPlugin 后台接收器
                val flutterIntent = Intent(context, es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java).apply {
                    data = android.net.Uri.parse("todowidget://markdone/$todoId")
                    action = "es.antonborri.home_widget.action.BACKGROUND"
                }
                context.sendBroadcast(flutterIntent)
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

            // ===============================================
            // 1. 给整个小部件（空白处）设置点击事件：启动 App
            // ===============================================
            val appIntent = Intent(context, MainActivity::class.java)
            val appPendingIntent = PendingIntent.getActivity(
                context, 0, appIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, appPendingIntent)

            // ===============================================
            // 2. 循环处理待办数据：渲染 UI 与复选框点击事件
            // ===============================================
            for (i in 1..3) {
                val layoutId = context.resources.getIdentifier("todo_layout_$i", "id", context.packageName)
                val textId = context.resources.getIdentifier("todo_text_$i", "id", context.packageName)
                val checkboxId = context.resources.getIdentifier("todo_checkbox_$i", "id", context.packageName)

                val title = widgetData.getString("todo_$i", "")
                val isDone = widgetData.getBoolean("todo_${i}_done", false)
                val id = widgetData.getString("todo_${i}_id", "")

                if (!title.isNullOrEmpty()) {
                    views.setViewVisibility(layoutId, View.VISIBLE)

                    if (isDone) {
                        // 修复点：将 VERSION.CODES 改为 VERSION_CODES
                        val spanned = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                            Html.fromHtml("<s>$title</s>", Html.FROM_HTML_MODE_LEGACY)
                        } else {
                            @Suppress("DEPRECATION")
                            Html.fromHtml("<s>$title</s>")
                        }
                        views.setCharSequence(textId, "setText", spanned)
                        views.setTextColor(textId, android.graphics.Color.parseColor("#999999"))
                        views.setImageViewResource(checkboxId, R.drawable.widget_checkbox_checked)
                    } else {
                        views.setTextViewText(textId, title)
                        views.setTextColor(textId, android.graphics.Color.parseColor("#333333"))
                        views.setImageViewResource(checkboxId, R.drawable.widget_checkbox_empty)
                    }

                    // 👉 核心修改：发送纯净的、自定义的 Action。由本类的 onReceive 拦截。
                    if (!id.isNullOrEmpty()) {
                        val clickIntent = Intent(context, TodoWidgetProvider::class.java).apply {
                            action = "MARK_TODO_DONE"
                            putExtra("todo_id", id)
                            // 加上这行确保系统更新机制正确
                            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
                        }

                        val pendingIntent = PendingIntent.getBroadcast(
                            context,
                            i * 100, // 确保 request code 唯一
                            clickIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )

                        // 只给复选框绑定后台打勾事件
                        views.setOnClickPendingIntent(checkboxId, pendingIntent)
                    }
                } else {
                    if (i == 1) {
                        views.setViewVisibility(layoutId, View.VISIBLE)
                        views.setTextViewText(textId, "今天太棒了，没有待办！")
                        views.setTextColor(textId, android.graphics.Color.parseColor("#333333"))
                        views.setImageViewResource(checkboxId, R.drawable.widget_checkbox_empty)
                        // 空状态时绑定空事件防止误触
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