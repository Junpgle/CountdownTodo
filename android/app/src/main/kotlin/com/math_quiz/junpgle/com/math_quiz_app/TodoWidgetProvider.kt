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

    private fun dpToPx(context: Context, dp: Int): Int {
        val density = context.resources.displayMetrics.density
        return (dp * density + 0.5f).toInt()
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
        
        val widgetMode = widgetData.getString("widget_mode", "todo") ?: "todo"
        val lastWidgetMode = localPrefs.getString("last_widget_mode", "todo") ?: "todo"

        // 🚀 自动导航逻辑 (优先级：课程 > 专注状态变化)
        var tabChanged = false
        if (urgentCourseId.isNotEmpty() && urgentCourseId != lastAutoCourseId) {
            currentTab = 1 // 课程页
            localPrefs.edit().putString("last_auto_course_id", urgentCourseId).apply()
            tabChanged = true
        } else if (widgetMode == "focus" && lastWidgetMode != "focus") {
            currentTab = 3 // 专注页 (活跃计时)
            tabChanged = true
        } else if (widgetMode != "focus" && lastWidgetMode == "focus") {
            currentTab = 0 // 切回待办
            tabChanged = true
        }

        if (tabChanged) {
            localPrefs.edit().putInt("current_widget_tab", currentTab).apply()
        }
        localPrefs.edit().putString("last_widget_mode", widgetMode).apply()

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
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)

            // 🚀 极致平衡：根据像素密度缩放安全距离 (Safe Distance in Pixels)
            val isSmallHeight = minHeight < 120
            // 更紧凑的内边距设置（比之前更小）
            val sidePaddingPx = dpToPx(context, if (minWidth < 120) 8 else 12)
            val topPaddingPx = dpToPx(context, if (isSmallHeight) 10 else 12)
            val bottomPaddingPx = dpToPx(context, if (isSmallHeight) 8 else 10)
            val headerSpacingPx = dpToPx(context, if (isSmallHeight) 4 else 8)

            // 使用较小的损耗估算，给每一行更多可用空间
            val dpTop = if (isSmallHeight) 10 else 12
            val dpBottom = if (isSmallHeight) 8 else 10
            val baseLossDp = dpTop + dpBottom + 16 + (if (isSmallHeight) 4 else 8) + 6
            val availableHeightDp = minHeight - baseLossDp

            // 将每行所需 DP 降低，让更多行可见（todo 改为 30 而不是 38）
            val maxTodoSlots = minOf(maxOf(1, availableHeightDp / 30), 8)
            val maxCourseSlots = minOf(maxOf(1, availableHeightDp / 70), 8)
            val maxCdSlots = minOf(maxOf(1, availableHeightDp / 36), 8)
            val maxTagSlots = minOf(maxOf(1, (availableHeightDp - 8) / 36), 8)

            // 修复：setViewPadding 必须接收像素值 (Pixels)
            views.setViewPadding(R.id.main_container, sidePaddingPx, topPaddingPx, sidePaddingPx, bottomPaddingPx)
            views.setViewPadding(R.id.tabs_layout, 0, 0, 0, headerSpacingPx)


            // 隐藏低优元素 & 动态调整字体 (Tab 使用 15sp/13sp 显得更大气)
            views.setViewVisibility(R.id.tl_total, if (isSmallHeight) View.GONE else View.VISIBLE)
            
            val tabIds = intArrayOf(R.id.tab_todo, R.id.tab_course, R.id.tab_countdown, R.id.tab_timelog)
            for (tid in tabIds) {
                views.setFloat(tid, "setTextSize", if (isSmallHeight) 13f else 15f)
            }

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
                if (title.isNullOrEmpty() || i > maxCdSlots) { views.setViewVisibility(layoutId, View.GONE); continue }

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
            val focusActiveLayoutId = context.resources.getIdentifier("focus_active_layout", "id", context.packageName)
            if (focusActiveLayoutId != 0) {
                if (widgetMode == "focus") {
                    views.setViewVisibility(focusActiveLayoutId, View.VISIBLE)
                    val fTitle = widgetData.getString("focus_title", "专注中")
                    val fTimer = widgetData.getString("focus_timer", "")
                    val titleId = context.resources.getIdentifier("focus_title", "id", context.packageName)
                    val timerId = context.resources.getIdentifier("focus_timer", "id", context.packageName)
                    val tagsId = context.resources.getIdentifier("focus_tags", "id", context.packageName)
                    
                    if (titleId != 0) {
                        views.setTextViewText(titleId, fTitle)
                        views.setViewVisibility(titleId, if (isSmallHeight) View.GONE else View.VISIBLE)
                    }
                    if (timerId != 0) {
                        views.setTextViewText(timerId, fTimer)
                        views.setFloat(timerId, "setTextSize", if (isSmallHeight) 18f else 22f)
                    }
                    if (tagsId != 0) {
                        val tagCountStr = widgetData.getString("focus_tag_count", "0") ?: "0"
                        val tagCount = try { tagCountStr.toInt() } catch (e: Exception) { 0 }
                        val tagsList = mutableListOf<String>()
                        for (i in 1..8) {
                            val tag = widgetData.getString("focus_tag_$i", "")
                            if (!tag.isNullOrEmpty()) tagsList.add(tag)
                        }
                        views.setTextViewText(tagsId, tagsList.joinToString(" • "))
                        views.setViewVisibility(tagsId, if (tagsList.isEmpty()) View.GONE else View.VISIBLE)
                    }
                } else {
                    views.setViewVisibility(focusActiveLayoutId, View.GONE)
                }
            }

            val tlTotalId = context.resources.getIdentifier("tl_total", "id", context.packageName)
            if (tlTotalId != 0) {
                val tlTotalText = widgetData.getString("tl_total", "今日专注: 0 分钟")
                views.setTextViewText(tlTotalId, tlTotalText)
                views.setTextColor(tlTotalId, secondaryTextColor) // 🚀 动态着色
            }

            // === 专注标签统计（tl_tag_*） ===
            // 读取标签数量，按键名 tl_tag_name_1..N 与 tl_tag_mins_1..N 渲染
            val tagCountStr = widgetData.getString("tl_tag_count", "0") ?: "0"
            val tagCount = try { Integer.parseInt(tagCountStr) } catch (e: Exception) { 0 }
            var hasTags = false
            for (i in 1..8) {
                val tagLayoutId = context.resources.getIdentifier("tl_tag_layout_$i", "id", context.packageName)
                if (tagLayoutId == 0) continue
                val tagName = widgetData.getString("tl_tag_name_$i", "")
                val tagMins = widgetData.getString("tl_tag_mins_$i", "")
                if (tagName.isNullOrEmpty() || i > maxTagSlots) { views.setViewVisibility(tagLayoutId, View.GONE); continue }

                hasTags = true
                views.setViewVisibility(tagLayoutId, View.VISIBLE)
                val tagNameId = context.resources.getIdentifier("tl_tag_name_$i", "id", context.packageName)
                val tagMinsId = context.resources.getIdentifier("tl_tag_mins_$i", "id", context.packageName)
                if (tagNameId != 0) {
                    views.setTextViewText(tagNameId, tagName)
                    views.setTextColor(tagNameId, primaryTextColor)
                }
                if (tagMinsId != 0) {
                    views.setTextViewText(tagMinsId, tagMins)
                    views.setTextColor(tagMinsId, greenColor)
                }
            }

            // 当没有标签统计时，隐藏可能存在的标签容器占位
            val tlTagEmptyId = context.resources.getIdentifier("tl_tag_empty_layout", "id", context.packageName)
            val tlTagEmptyTextId = context.resources.getIdentifier("tl_tag_empty_text", "id", context.packageName)
            if (tlTagEmptyId != 0) views.setViewVisibility(tlTagEmptyId, if (hasTags) View.GONE else View.VISIBLE)
            if (tlTagEmptyTextId != 0) views.setTextColor(tlTagEmptyTextId, secondaryTextColor)

            // 全局跳转
            val appIntent = Intent(context, MainActivity::class.java)
            val appPendingIntent = PendingIntent.getActivity(context, 0, appIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_root, appPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}