package com.math_quiz.junpgle.com.math_quiz_app

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.Button
import android.widget.ListView
import android.widget.TextView

class RecurrenceWidgetConfigureActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private lateinit var seriesList: ListView
    private lateinit var emptyContainer: View

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_recurrence_widget_configure)

        appWidgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        val canceledResult = Intent().apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        setResult(RESULT_CANCELED, canceledResult)
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        seriesList = findViewById(R.id.recurrence_series_list)
        emptyContainer = findViewById(R.id.recurrence_config_empty)

        findViewById<Button>(R.id.recurrence_config_open_app).setOnClickListener {
            startActivity(Intent(this, MainActivity::class.java))
        }
        findViewById<Button>(R.id.recurrence_config_cancel).setOnClickListener {
            finish()
        }
    }

    override fun onResume() {
        super.onResume()
        if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
            reloadSeries()
        }
    }

    private fun reloadSeries() {
        val widgetData = getSharedPreferences(
            RecurrenceWidgetData.HOME_WIDGET_PREFERENCES,
            Context.MODE_PRIVATE
        )
        val items = RecurrenceWidgetData.readSeries(widgetData).filter { it.isActive }
        val selectedId = RecurrenceWidgetData.selectedSeriesId(this, appWidgetId)

        seriesList.visibility = if (items.isEmpty()) View.GONE else View.VISIBLE
        emptyContainer.visibility = if (items.isEmpty()) View.VISIBLE else View.GONE
        seriesList.adapter = RecurrenceSeriesAdapter(items, selectedId)
        seriesList.setOnItemClickListener { _, _, position, _ ->
            selectSeries(items[position])
        }
    }

    private fun selectSeries(series: RecurrenceWidgetSeries) {
        RecurrenceWidgetData.saveSelectedSeriesId(this, appWidgetId, series.seriesId)

        sendBroadcast(
            Intent(this, RecurrenceWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(appWidgetId))
            }
        )

        val result = Intent().apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        setResult(RESULT_OK, result)
        finish()
    }

    private inner class RecurrenceSeriesAdapter(
        private val items: List<RecurrenceWidgetSeries>,
        private val selectedId: String?
    ) : BaseAdapter() {
        override fun getCount(): Int = items.size

        override fun getItem(position: Int): RecurrenceWidgetSeries = items[position]

        override fun getItemId(position: Int): Long = position.toLong()

        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val view = convertView ?: LayoutInflater.from(this@RecurrenceWidgetConfigureActivity)
                .inflate(R.layout.item_recurrence_widget_series, parent, false)
            val item = getItem(position)

            view.findViewById<TextView>(R.id.recurrence_config_item_title).text = item.title
            view.findViewById<TextView>(R.id.recurrence_config_item_meta).text = buildList {
                add(item.recurrenceText)
                item.contextText?.takeIf { it.isNotBlank() }?.let(::add)
                add("已完成 ${item.completedCount} 期")
            }.joinToString(" · ")
            view.findViewById<TextView>(R.id.recurrence_config_item_selected).visibility =
                if (item.seriesId == selectedId) View.VISIBLE else View.INVISIBLE
            return view
        }
    }
}
