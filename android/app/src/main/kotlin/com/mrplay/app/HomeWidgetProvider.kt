package com.mrplay.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

class HomeWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences
  ) {
    val items = parseRecent(widgetData.getString("recent", null))
    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.mrplay_widget).apply {
        setOnClickPendingIntent(
            R.id.widget_header, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
        fillRow(context, this, R.id.widget_item_1, items.getOrNull(0))
        fillRow(context, this, R.id.widget_item_2, items.getOrNull(1))
        fillRow(context, this, R.id.widget_item_3, items.getOrNull(2))
      }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  private fun fillRow(
      context: Context,
      views: RemoteViews,
      viewId: Int,
      item: RecentItem?
  ) {
    if (item == null || item.title.isBlank()) {
      views.setViewVisibility(viewId, View.GONE)
      return
    }
    views.setViewVisibility(viewId, View.VISIBLE)
    views.setTextViewText(viewId, item.title)
    val uri =
        Uri.parse("mrplay://open")
            .buildUpon()
            .appendQueryParameter("url", item.url)
            .build()
    views.setOnClickPendingIntent(
        viewId, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri))
  }

  private fun parseRecent(raw: String?): List<RecentItem> {
    if (raw.isNullOrEmpty()) return emptyList()
    return try {
      val array = JSONArray(raw)
      val items = mutableListOf<RecentItem>()
      for (i in 0 until array.length()) {
        val obj = array.optJSONObject(i) ?: continue
        items.add(RecentItem(obj.optString("title"), obj.optString("url")))
      }
      items
    } catch (_: Exception) {
      emptyList()
    }
  }

  data class RecentItem(val title: String, val url: String)
}
