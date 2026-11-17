package com.math_quiz.junpgle.com.math_quiz_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject

/**
 * A compact monthly finance summary widget.
 *
 * Flutter writes the snapshot into the same HomeWidget preferences used by
 * the other widgets. Data entry stays in the Flutter finance screen.
 */
class FinanceOnlyWidgetProvider : HomeWidgetProvider() {

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateWidget(
            context,
            appWidgetManager,
            appWidgetId,
            WidgetProviderSupport.preferences(context),
            newOptions
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (!WidgetProviderSupport.isUpdateAction(intent)) return

        val appWidgetManager = AppWidgetManager.getInstance(context)
        val appWidgetIds = WidgetProviderSupport.widgetIds(
            context,
            intent,
            FinanceOnlyWidgetProvider::class.java
        )
        if (appWidgetIds.isNotEmpty()) {
            onUpdate(
                context,
                appWidgetManager,
                appWidgetIds,
                WidgetProviderSupport.preferences(context)
            )
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(
                context,
                appWidgetManager,
                appWidgetId,
                widgetData,
                appWidgetManager.getAppWidgetOptions(appWidgetId)
            )
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences,
        options: Bundle
    ) {
        val layoutId = layoutFor(options)
        val views = RemoteViews(context.packageName, layoutId)
        WidgetProviderSupport.applyCommonChrome(context, views, R.id.widget_title)

        views.setTextViewText(
            R.id.finance_month_label,
            widgetData.getString("finance_month_label", "本月")
        )
        views.setTextViewText(
            R.id.finance_transaction_count,
            widgetData.getString("finance_transaction_count", "0 笔")
        )
        views.setTextViewText(
            R.id.finance_expense,
            widgetData.getString("finance_expense", "¥0.00")
        )
        views.setTextViewText(
            R.id.finance_income,
            widgetData.getString("finance_income", "¥0.00")
        )
        views.setTextViewText(
            R.id.finance_balance,
            widgetData.getString("finance_balance", "¥0.00")
        )
        views.setTextViewText(
            R.id.finance_latest_title,
            widgetData.getString("finance_latest_title", "本月还没有账单")
        )
        views.setTextViewText(
            R.id.finance_latest_amount,
            widgetData.getString("finance_latest_amount", "")
        )

        val latestDate = widgetData.getString("finance_latest_date", "") ?: ""
        views.setTextViewText(
            R.id.finance_latest_date,
            if (latestDate.isEmpty()) "点击记一笔开始记录" else latestDate
        )

        if (layoutId == R.layout.widget_finance_large) {
            bindRecentTransactions(context, views, widgetData)
        }

        views.setOnClickPendingIntent(
            R.id.finance_add_button,
            financePendingIntent(context, "countdowntodo://finance/entry", 2001)
        )
        views.setOnClickPendingIntent(
            android.R.id.background,
            financePendingIntent(context, "countdowntodo://finance", 2000)
        )

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun bindRecentTransactions(
        context: Context,
        views: RemoteViews,
        widgetData: SharedPreferences
    ) {
        val rows = listOf(
            RecentRowIds(
                R.id.finance_recent_row_0,
                R.id.finance_recent_title_0,
                R.id.finance_recent_date_0,
                R.id.finance_recent_amount_0
            ),
            RecentRowIds(
                R.id.finance_recent_row_1,
                R.id.finance_recent_title_1,
                R.id.finance_recent_date_1,
                R.id.finance_recent_amount_1
            ),
            RecentRowIds(
                R.id.finance_recent_row_2,
                R.id.finance_recent_title_2,
                R.id.finance_recent_date_2,
                R.id.finance_recent_amount_2
            ),
            RecentRowIds(
                R.id.finance_recent_row_3,
                R.id.finance_recent_title_3,
                R.id.finance_recent_date_3,
                R.id.finance_recent_amount_3
            )
        )

        val items = parseRecentTransactions(widgetData)
        views.setViewVisibility(
            R.id.finance_recent_empty,
            if (items.isEmpty()) View.VISIBLE else View.GONE
        )

        for ((index, row) in rows.withIndex()) {
            val item = items.getOrNull(index)
            if (item == null) {
                views.setViewVisibility(row.containerId, View.GONE)
                continue
            }
            views.setViewVisibility(row.containerId, View.VISIBLE)
            views.setTextViewText(row.titleId, item.title)
            views.setTextViewText(row.dateId, item.date)
            views.setTextViewText(row.amountId, item.amount)
            val colorRes = when (item.type) {
                "expense" -> R.color.widget_due_overdue
                "income" -> R.color.widget_success
                else -> R.color.widget_text_accent
            }
            WidgetProviderSupport.setTextColor(context, views, row.amountId, colorRes)
        }
    }

    private fun parseRecentTransactions(widgetData: SharedPreferences): List<RecentTransaction> {
        val rawJson = widgetData.getString("finance_recent_json", null)
        if (!rawJson.isNullOrBlank()) {
            try {
                val array = JSONArray(rawJson)
                val parsed = ArrayList<RecentTransaction>(array.length())
                for (i in 0 until minOf(array.length(), 4)) {
                    val obj: JSONObject = array.optJSONObject(i) ?: continue
                    val title = obj.optString("title", "").ifBlank { "记账记录" }
                    val amount = obj.optString("amount", "")
                    val type = obj.optString("type", "")
                    val date = obj.optString("date", "")
                    parsed.add(RecentTransaction(title, amount, type, date))
                }
                return parsed
            } catch (_: Exception) {
                // Fall through to legacy single-item fallback below.
            }
        }

        val latestAmount = widgetData.getString("finance_latest_amount", "") ?: ""
        val latestDate = widgetData.getString("finance_latest_date", "") ?: ""
        val latestTitle = widgetData.getString("finance_latest_title", "") ?: ""
        if (latestAmount.isEmpty() && latestDate.isEmpty()) {
            return emptyList()
        }
        val inferredType = if (latestAmount.startsWith("-")) "expense" else "income"
        return listOf(
            RecentTransaction(
                title = latestTitle.ifBlank { "记账记录" },
                amount = latestAmount,
                type = inferredType,
                date = latestDate
            )
        )
    }

    private data class RecentRowIds(
        val containerId: Int,
        val titleId: Int,
        val dateId: Int,
        val amountId: Int
    )

    private data class RecentTransaction(
        val title: String,
        val amount: String,
        val type: String,
        val date: String
    )

    /**
     * Android reports the currently allocated size in dp through widget options.
     * Keep the thresholds cell-oriented: roughly 2 cells is 110dp, 3 cells
     * is 180dp, and taller tablet/4x4 widgets (>= 200dp) use the expanded list layout.
     */
    private fun layoutFor(options: Bundle): Int {
        val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

        return when {
            width == 0 || width < 200 -> R.layout.widget_finance_compact
            height in 1..149 -> R.layout.widget_finance_wide
            height >= 200 -> R.layout.widget_finance_large
            else -> R.layout.widget_finance
        }
    }

    private fun financePendingIntent(
        context: Context,
        uri: String,
        requestCode: Int
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse(uri)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
