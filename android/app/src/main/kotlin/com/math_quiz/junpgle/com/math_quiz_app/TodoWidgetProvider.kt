package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.text.Html
import android.text.Spanned
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

    private fun getHtmlSpanned(text: String?): Spanned {
        val safeText = text ?: ""
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
            Html.fromHtml(safeText, Html.FROM_HTML_MODE_LEGACY)
        } else {
            @Suppress("DEPRECATION") Html.fromHtml(safeText)
        }
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
            }
        }

        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE || intent.action == "es.antonborri.home_widget.action.UPDATE") {
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
        val localPrefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        var currentTab = localPrefs.getInt("current_widget_tab", 0)
        val urgentCourseId = widgetData.getString("urgent_course_id", "") ?: ""
        val lastAutoCourseId = localPrefs.getString("last_auto_course_id", "") ?: ""

        if (urgentCourseId.isNotEmpty() && urgentCourseId != lastAutoCourseId) {
            currentTab = 1
            localPrefs.edit().putInt("current_widget_tab", 1).putString("last_auto_course_id", urgentCourseId).apply()
        }

        // 🚀 动态嗅探系统深色模式
        val isDarkMode = (context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES

        // 🚀 深浅色调色板
        val primaryTextColor = android.graphics.Color.parseColor(if (isDarkMode) "#F3F4F6" else "#1F2937")
        val secondaryTextColor = android.graphics.Color.parseColor(if (isDarkMode) "#9CA3AF" else "#6B7280")
        val tabActiveColor = android.graphics.Color.parseColor(if (isDarkMode) "#F9FAFB" else "#111827")
        val tabInactiveColor = android.graphics.Color.parseColor(if (isDarkMode) "#6B7280" else "#9CA3AF")
        val redColor = android.graphics.Color.parseColor(if (isDarkMode) "#F87171" else "#EF4444")
        val greenColor = android.graphics.Color.parseColor(if (isDarkMode) "#34D399" else "#10B981")
        val blueColor = android.graphics.Color.parseColor(if (isDarkMode) "#60A5FA" else "#3B82F6")
        val yellowColor = android.graphics.Color.parseColor(if (isDarkMode) "#FBBF24" else "#F59E0B")
        val bgColor = android.graphics.Color.parseColor(if (isDarkMode) "#1E1E1E" else "#FFFFFF")

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_todo)

            // 🚀 为底层背景图片涂色，实现自动深色背景变换
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

            views.setViewVisibility(R.id.page_todos, if (currentTab == 0) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.page_courses, if (currentTab == 1) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.page_countdowns, if (currentTab == 2) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.page_timelogs, if (currentTab == 3) View.VISIBLE else View.GONE)

            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

            // 计算槽位限制
            val maxTodoSlots = minOf(maxOf(1, (minHeight - 75) / 34), 8)
            val maxCourseSlots = minOf(maxOf(1, (minHeight - 75) / 80), 8)

            // 1. 渲染待办 (Page 0)
            for (i in 1..8) {
                val layoutId = context.resources.getIdentifier("todo_layout_$i", "id", context.packageName)
                if (layoutId == 0) continue
                val title = widgetData.getString("todo_$i", "")
                if (title.isNullOrEmpty() || i > maxTodoSlots) { views.setViewVisibility(layoutId, View.GONE); continue }

                views.setViewVisibility(layoutId, View.VISIBLE)
                val textId = context.resources.getIdentifier("todo_text_$i", "id", context.packageName)
                val isDone = widgetData.getBoolean("todo_${i}_done", false)
                views.setCharSequence(textId, "setText", getHtmlSpanned(if (isDone) "<s>$title</s>" else title))

                // 🚀 设置待办文本颜色
                if (textId != 0) {
                    views.setTextColor(textId, if (isDone) secondaryTextColor else primaryTextColor)
                }

                // 复选框状态
                val checkboxId = context.resources.getIdentifier("todo_checkbox_$i", "id", context.packageName)
                val checkedResId = context.resources.getIdentifier(if (isDone) "widget_checkbox_checked" else "widget_checkbox_empty", "drawable", context.packageName)
                if (checkedResId != 0) views.setImageViewResource(checkboxId, checkedResId)

                val id = widgetData.getString("todo_${i}_id", "")
                if (!id.isNullOrEmpty()) {
                    val clickIntent = Intent(context, TodoWidgetProvider::class.java).apply {
                        action = "MARK_TODO_DONE"
                        putExtra("todo_id", id)
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
                    }
                    views.setOnClickPendingIntent(checkboxId, PendingIntent.getBroadcast(context, i * 100, clickIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                }

                val dueId = context.resources.getIdentifier("todo_due_$i", "id", context.packageName)
                val dueText = widgetData.getString("todo_${i}_due", "")
                if (!dueText.isNullOrEmpty() && !isDone) {
                    views.setViewVisibility(dueId, View.VISIBLE)
                    views.setTextViewText(dueId, dueText)
                    // 🚀 动态截止时间颜色
                    if (dueText.contains("逾期")) views.setTextColor(dueId, redColor)
                    else if (dueText.contains("今天")) views.setTextColor(dueId, yellowColor)
                    else views.setTextColor(dueId, greenColor)
                } else {
                    views.setViewVisibility(dueId, View.GONE)
                }
            }

            // 2. 课程提醒 (Page 1)
            var hasCourse = false
            for (i in 1..8) {
                val layoutId = context.resources.getIdentifier("course_layout_$i", "id", context.packageName)
                if (layoutId == 0) continue
                val cName = widgetData.getString("course_name_$i", "")
                if (cName.isNullOrEmpty() || i > maxCourseSlots) { views.setViewVisibility(layoutId, View.GONE); continue }

                hasCourse = true
                views.setViewVisibility(layoutId, View.VISIBLE)
                val dateId = context.resources.getIdentifier("course_date_$i", "id", context.packageName)
                val nameId = context.resources.getIdentifier("course_name_$i", "id", context.packageName)
                val timeId = context.resources.getIdentifier("course_time_$i", "id", context.packageName)
                val roomId = context.resources.getIdentifier("course_room_$i", "id", context.packageName)

                // 🚀 动态着色所有行
                if (dateId != 0) {
                    views.setCharSequence(dateId, "setText", getHtmlSpanned(widgetData.getString("course_date_$i", "")))
                    views.setTextColor(dateId, secondaryTextColor)
                }
                if (nameId != 0) {
                    views.setCharSequence(nameId, "setText", getHtmlSpanned(cName))
                    val cId = widgetData.getString("course_id_$i", "") ?: ""
                    views.setTextColor(nameId, if (cId == urgentCourseId && urgentCourseId.isNotEmpty()) redColor else primaryTextColor)
                }
                if (timeId != 0) {
                    views.setTextViewText(timeId, widgetData.getString("course_time_$i", ""))
                    views.setTextColor(timeId, secondaryTextColor)
                }
                if (roomId != 0) {
                    views.setTextViewText(roomId, widgetData.getString("course_room_$i", ""))
                    views.setTextColor(roomId, secondaryTextColor)
                }
            }

            // 🚀 空状态文字变色
            val courseEmptyId = context.resources.getIdentifier("course_empty_layout", "id", context.packageName)
            val courseEmptyTextId = context.resources.getIdentifier("course_empty_text", "id", context.packageName)
            if (courseEmptyId != 0) views.setViewVisibility(courseEmptyId, if (hasCourse) View.GONE else View.VISIBLE)
            if (courseEmptyTextId != 0) views.setTextColor(courseEmptyTextId, secondaryTextColor)

            // 3. 倒数日
            var hasCd = false
            for (i in 1..8) {
                val layoutId = context.resources.getIdentifier("cd_layout_$i", "id", context.packageName)
                if (layoutId == 0) continue
                val title = widgetData.getString("cd_title_$i", "")
                if (title.isNullOrEmpty() || i > maxTodoSlots) { views.setViewVisibility(layoutId, View.GONE); continue }

                hasCd = true
                views.setViewVisibility(layoutId, View.VISIBLE)
                val titleId = context.resources.getIdentifier("cd_title_$i", "id", context.packageName)
                val daysId = context.resources.getIdentifier("cd_days_$i", "id", context.packageName)

                // 🚀 动态着色
                if (titleId != 0) {
                    views.setCharSequence(titleId, "setText", getHtmlSpanned(title))
                    views.setTextColor(titleId, primaryTextColor)
                }
                if (daysId != 0) {
                    views.setTextViewText(daysId, widgetData.getString("cd_days_$i", ""))
                    views.setTextColor(daysId, blueColor)
                }
            }

            // 🚀 空状态文字变色
            val cdEmptyId = context.resources.getIdentifier("cd_empty_layout", "id", context.packageName)
            val cdEmptyTextId = context.resources.getIdentifier("cd_empty_text", "id", context.packageName)
            if (cdEmptyId != 0) views.setViewVisibility(cdEmptyId, if (hasCd) View.GONE else View.VISIBLE)
            if (cdEmptyTextId != 0) views.setTextColor(cdEmptyTextId, secondaryTextColor)

            // 4. 专注记录
            val tlTotalId = context.resources.getIdentifier("tl_total", "id", context.packageName)
            if (tlTotalId != 0) {
                val tlTotalText = widgetData.getString("tl_total", "今日专注: 0 分钟")
                views.setTextViewText(tlTotalId, tlTotalText)
                views.setTextColor(tlTotalId, secondaryTextColor) // 🚀 动态着色
            }

            var hasTl = false
            for (i in 1..8) {
                val layoutId = context.resources.getIdentifier("tl_layout_$i", "id", context.packageName)
                if (layoutId == 0) continue
                val title = widgetData.getString("tl_title_$i", "")
                if (title.isNullOrEmpty() || i > maxTodoSlots) { views.setViewVisibility(layoutId, View.GONE); continue }

                hasTl = true
                views.setViewVisibility(layoutId, View.VISIBLE)
                val titleId = context.resources.getIdentifier("tl_title_$i", "id", context.packageName)
                val timeId = context.resources.getIdentifier("tl_time_$i", "id", context.packageName)

                // 🚀 动态着色
                if (titleId != 0) {
                    views.setTextViewText(titleId, title)
                    views.setTextColor(titleId, primaryTextColor)
                }
                if (timeId != 0) {
                    views.setTextViewText(timeId, widgetData.getString("tl_time_$i", ""))
                    views.setTextColor(timeId, greenColor)
                }
            }

            // 🚀 空状态文字变色
            val tlEmptyId = context.resources.getIdentifier("tl_empty_layout", "id", context.packageName)
            val tlEmptyTextId = context.resources.getIdentifier("tl_empty_text", "id", context.packageName)
            if (tlEmptyId != 0) views.setViewVisibility(tlEmptyId, if (hasTl) View.GONE else View.VISIBLE)
            if (tlEmptyTextId != 0) views.setTextColor(tlEmptyTextId, secondaryTextColor)

            // 全局跳转
            val appIntent = Intent(context, MainActivity::class.java)
            val appPendingIntent = PendingIntent.getActivity(context, 0, appIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_root, appPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}