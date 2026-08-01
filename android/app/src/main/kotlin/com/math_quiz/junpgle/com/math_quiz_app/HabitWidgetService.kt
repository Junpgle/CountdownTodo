package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class HabitWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return HabitRemoteViewsFactory(this.applicationContext, intent)
    }
}

class HabitRemoteViewsFactory(
    private val context: Context,
    private val intent: Intent
) : RemoteViewsService.RemoteViewsFactory {

    private val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
    private val itemsData = mutableListOf<Bundle>()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        itemsData.clear()
        for (i in 1..5) {
            val title = prefs.getString("habit_title_$i", "")
            if (title.isNullOrEmpty()) continue
            val bundle = Bundle()
            bundle.putString("title", title)
            bundle.putString("icon", prefs.getString("habit_icon_$i", ""))
            bundle.putString("progress", prefs.getString("habit_progress_$i", ""))
            bundle.putBoolean("met", prefs.getBoolean("habit_met_$i", false))
            bundle.putInt("pct", (prefs.all["habit_pct_$i"] as? Number)?.toInt() ?: 0)
            bundle.putString("habitId", prefs.getString("habit_id_$i", ""))
            bundle.putString("source", prefs.getString("habit_source_$i", ""))
            bundle.putString("quick", prefs.getString("habit_quick_$i", ""))
            itemsData.add(bundle)
        }
    }

    override fun onDestroy() {
        itemsData.clear()
    }

    override fun getCount(): Int = itemsData.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position >= itemsData.size) {
            return RemoteViews(context.packageName, R.layout.widget_item_habit)
        }
        val data = itemsData[position]
        val isDarkMode =
            (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
        val primaryTextColor = context.getColor(R.color.widget_text_primary)
        val secondaryTextColor = context.getColor(R.color.widget_text_secondary)
        val successColor = context.getColor(R.color.widget_success)
        val accentColor = context.getColor(R.color.widget_accent)

        val views = RemoteViews(context.packageName, R.layout.widget_item_habit)
        val isMet = data.getBoolean("met")

        views.setTextViewText(R.id.habit_icon, data.getString("icon", "").ifEmpty { "🎯" })
        views.setTextViewText(R.id.habit_title, data.getString("title", ""))
        views.setTextColor(R.id.habit_title, primaryTextColor)

        val progressText = data.getString("progress", "")
        if (progressText.isNotEmpty()) {
            views.setViewVisibility(R.id.habit_progress, View.VISIBLE)
            views.setTextViewText(R.id.habit_progress, progressText)
            views.setTextColor(
                R.id.habit_progress,
                if (isMet) successColor else secondaryTextColor
            )
        } else {
            views.setViewVisibility(R.id.habit_progress, View.GONE)
        }

        // 未达标：显示快捷打卡按钮（＋快捷值）；达标：显示 ✅。
        val habitId = data.getString("habitId", "") ?: ""
        val source = data.getString("source", "") ?: ""
        if (isMet) {
            views.setTextViewText(R.id.habit_met, "✅")
            views.setTextColor(R.id.habit_met, successColor)
        } else {
            val quickText = data.getString("quick", "")
            val firstQuick = quickText.split(",").firstOrNull { it.isNotBlank() } ?: ""
            val label = if (firstQuick.isNotEmpty()) "+$firstQuick" else "＋"
            views.setTextViewText(R.id.habit_met, label)
            views.setTextColor(R.id.habit_met, accentColor)
        }

        // 时长型习惯无法在后台打卡：点击打开应用由用户手动开始专注。
        val canQuickCheckIn = source != "pomodoroTag" && habitId.isNotEmpty()
        if (canQuickCheckIn) {
            val quickText = data.getString("quick", "")
            val firstQuick = quickText.split(",").firstOrNull { it.isNotBlank() } ?: ""
            val checkInIntent = Intent(context, HabitWidgetProvider::class.java).apply {
                action = "QUICK_CHECKIN"
                putExtra("habit_id", habitId)
                putExtra("habit_value", firstQuick)
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0))
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context, 100 + position, checkInIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.habit_met, pendingIntent)
        }

        // 进度条：XML 默认主题色；达标时覆盖为绿色（RemoteViews 反射调用）
        if (isMet) {
            views.setInt(R.id.habit_progress_bar, "setProgressTint", successColor)
        }
        views.setInt(R.id.habit_progress_bar, "setProgress", data.getInt("pct", 0))
        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
