package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
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

    private fun getTabIntent(context: Context, tabIndex: Int, appWidgetIds: IntArray): PendingIntent {
        val intent = Intent(context, TodoWidgetProvider::class.java).apply {
            action = "SWITCH_TAB"
            putExtra("tab_index", tabIndex)
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
        }
        return PendingIntent.getBroadcast(
            context, tabIndex, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val appWidgetIds = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
            ?: appWidgetManager.getAppWidgetIds(ComponentName(context, TodoWidgetProvider::class.java))

        if (intent.action == "SWITCH_TAB") {
            val tabIndex = intent.getIntExtra("tab_index", 0)
            prefs.edit().putInt("current_widget_tab", tabIndex).apply()
            if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                onUpdate(context, appWidgetManager, appWidgetIds, prefs)
            }
        }

        if (intent.action == "MARK_TODO_DONE") {
            val todoId = intent.getStringExtra("todo_id")
            if (todoId != null) {
                val flutterIntent = Intent(context, es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java).apply {
                    data = android.net.Uri.parse("todowidget://markdone/$todoId")
                    action = "es.antonborri.home_widget.action.BACKGROUND"
                }
                context.sendBroadcast(flutterIntent)
                // 延迟一小会儿刷新列表，让勾选动画或状态在 Flutter 处理后同步过来
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.list_todos)
            }
        }

        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE || intent.action == "es.antonborri.home_widget.action.UPDATE") {
            if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                onUpdate(context, appWidgetManager, appWidgetIds, prefs)
                // 通知所有 ListView 重新拉取数据
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.list_todos)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.list_courses)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.list_countdowns)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.list_timelogs)
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val localPrefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        var currentTab = localPrefs.getInt("current_widget_tab", 0)

        val urgentCourseId = widgetData.getString("urgent_course_id", "") ?: ""
        val lastAutoCourseId = localPrefs.getString("last_auto_course_id", "") ?: ""
        val widgetMode = widgetData.getString("widget_mode", "todo") ?: "todo"
        val lastWidgetMode = localPrefs.getString("last_widget_mode", "todo") ?: "todo"

        // 🚀 自动导航逻辑
        var tabChanged = false
        if (urgentCourseId.isNotEmpty() && urgentCourseId != lastAutoCourseId) {
            currentTab = 1
            localPrefs.edit().putString("last_auto_course_id", urgentCourseId).apply()
            tabChanged = true
        } else if (widgetMode == "focus" && lastWidgetMode != "focus") {
            currentTab = 3
            tabChanged = true
        } else if (widgetMode != "focus" && lastWidgetMode == "focus") {
            currentTab = 0
            tabChanged = true
        }

        if (tabChanged) {
            localPrefs.edit().putInt("current_widget_tab", currentTab).apply()
        }
        localPrefs.edit().putString("last_widget_mode", widgetMode).apply()

        // 🚀 动态嗅探系统深色模式
        val isDarkMode = (context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES
        val tabActiveColor = android.graphics.Color.parseColor(if (isDarkMode) "#F9FAFB" else "#111827")
        val tabInactiveColor = android.graphics.Color.parseColor(if (isDarkMode) "#6B7280" else "#9CA3AF")
        val bgColor = android.graphics.Color.parseColor(if (isDarkMode) "#1E1E1E" else "#FFFFFF")

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_todo)

            // 背景变色
            val bgImageId = context.resources.getIdentifier("widget_bg_image", "id", context.packageName)
            if (bgImageId != 0) {
                views.setInt(bgImageId, "setColorFilter", bgColor)
            }

            // Tabs 颜色与交互
            views.setOnClickPendingIntent(R.id.tab_todo, getTabIntent(context, 0, appWidgetIds))
            views.setOnClickPendingIntent(R.id.tab_course, getTabIntent(context, 1, appWidgetIds))
            views.setOnClickPendingIntent(R.id.tab_countdown, getTabIntent(context, 2, appWidgetIds))
            views.setOnClickPendingIntent(R.id.tab_timelog, getTabIntent(context, 3, appWidgetIds))

            views.setTextColor(R.id.tab_todo, if (currentTab == 0) tabActiveColor else tabInactiveColor)
            views.setTextColor(R.id.tab_course, if (currentTab == 1) tabActiveColor else tabInactiveColor)
            views.setTextColor(R.id.tab_countdown, if (currentTab == 2) tabActiveColor else tabInactiveColor)
            views.setTextColor(R.id.tab_timelog, if (currentTab == 3) tabActiveColor else tabInactiveColor)

            // 控制页面显示
            views.setViewVisibility(R.id.page_todos, if (currentTab == 0) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.page_courses, if (currentTab == 1) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.page_countdowns, if (currentTab == 2) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.page_timelogs, if (currentTab == 3) View.VISIBLE else View.GONE)

            // 🚀 绑定四大列表的数据源 (RemoteViewsService)
            fun getServiceIntent(listType: Int): Intent {
                return Intent(context, TodoWidgetService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    putExtra("list_type", listType)
                    data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                }
            }
            views.setRemoteAdapter(R.id.list_todos, getServiceIntent(0))
            views.setRemoteAdapter(R.id.list_courses, getServiceIntent(1))
            views.setRemoteAdapter(R.id.list_countdowns, getServiceIntent(2))
            views.setRemoteAdapter(R.id.list_timelogs, getServiceIntent(3))

            // 设置空状态视图
            views.setEmptyView(R.id.list_todos, R.id.empty_todos)
            views.setEmptyView(R.id.list_courses, R.id.empty_courses)
            views.setEmptyView(R.id.list_countdowns, R.id.empty_countdowns)
            views.setEmptyView(R.id.list_timelogs, R.id.empty_timelogs)

            // 🚀 设置待办点击事件模板 (极其重要，配合 Service 里的 FillInIntent)
            val clickIntent = Intent(context, TodoWidgetProvider::class.java).apply {
                action = "MARK_TODO_DONE"
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
            }
            val clickPendingIntent = PendingIntent.getBroadcast(
                context, 0, clickIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE // 此处必须是 MUTABLE
            )
            views.setPendingIntentTemplate(R.id.list_todos, clickPendingIntent)


            // 全局跳转模板 (处理课程、倒数的点击，直接打开APP)
            val appIntent = Intent(context, MainActivity::class.java)
            val appPendingIntent = PendingIntent.getActivity(context, 0, appIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
            views.setPendingIntentTemplate(R.id.list_courses, appPendingIntent)
            views.setPendingIntentTemplate(R.id.list_countdowns, appPendingIntent)
            views.setPendingIntentTemplate(R.id.list_timelogs, appPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, 0, appIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))

            // 专注状态栏静态处理
            val focusActiveLayoutId = context.resources.getIdentifier("focus_active_layout", "id", context.packageName)
            if (focusActiveLayoutId != 0) {
                if (widgetMode == "focus") {
                    views.setViewVisibility(focusActiveLayoutId, View.VISIBLE)
                    views.setTextViewText(R.id.focus_title, widgetData.getString("focus_title", "专注中"))
                    views.setTextViewText(R.id.focus_timer, widgetData.getString("focus_timer", ""))
                    val tagsList = mutableListOf<String>()
                    for (i in 1..8) {
                        val tag = widgetData.getString("focus_tag_$i", "")
                        if (!tag.isNullOrEmpty()) tagsList.add(tag)
                    }
                    views.setTextViewText(R.id.focus_tags, tagsList.joinToString(" • "))
                    views.setViewVisibility(R.id.focus_tags, if (tagsList.isEmpty()) View.GONE else View.VISIBLE)
                } else {
                    views.setViewVisibility(focusActiveLayoutId, View.GONE)
                }
            }
            views.setTextViewText(R.id.tl_total, widgetData.getString("tl_total", "今日专注: 0 分钟"))

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}