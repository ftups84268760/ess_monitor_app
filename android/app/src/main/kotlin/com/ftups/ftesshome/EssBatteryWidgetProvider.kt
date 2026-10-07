package com.ftups.ftesshome

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class EssBatteryWidgetProvider : AppWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "es.antonborri.home_widget.action.BACKGROUND_UPDATE") {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, EssBatteryWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            onUpdate(context, appWidgetManager, appWidgetIds)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            // 🎯 防彈裝甲：用 try-catch 包覆整個更新邏輯，確保原生端錯誤絕不會拖垮 Flutter App
            try {
                val widgetData = HomeWidgetPlugin.getData(context)

                // 🎯 動態型別解析：避免開發期遺留的髒資料引發 ClassCastException
                val soc = when (val s = widgetData.all["battery_soc"]) {
                    is Number -> s.toInt()
                    is String -> s.toIntOrNull() ?: 0
                    else -> 0
                }

                val deviceName = widgetData.all["device_name"]?.toString() ?: "載入中..."

                val isCharging = when (val c = widgetData.all["is_charging"]) {
                    is Boolean -> c
                    is String -> c.toBoolean()
                    else -> false
                }

                val lastUpdateSeconds = when (val t = widgetData.all["last_update_timestamp"]) {
                    is Number -> t.toLong()
                    is String -> t.toFloatOrNull()?.toLong() ?: (System.currentTimeMillis() / 1000)
                    else -> (System.currentTimeMillis() / 1000)
                }

                val nowSeconds = System.currentTimeMillis() / 1000
                val diff = nowSeconds - lastUpdateSeconds
                val timeStr = when {
                    diff < 60 -> "剛剛"
                    diff < 3600 -> "${diff / 60} 分鐘前"
                    diff < 86400 -> "${diff / 3600} 小時前"
                    else -> "${diff / 86400} 天前"
                }

                val views = RemoteViews(context.packageName, R.layout.widget_ess_battery)

                views.setTextViewText(R.id.tv_device_name, deviceName)
                views.setTextViewText(R.id.tv_soc, "$soc%")
                views.setTextViewText(R.id.tv_time, timeStr)

                val fillLevel = maxOf(soc * 100, 500)
                views.setInt(R.id.img_battery_fill, "setImageLevel", fillLevel)

                views.setProgressBar(R.id.pb_soc, 100, soc, false)

                if (isCharging) {
                    views.setViewVisibility(R.id.img_charging_icon, View.VISIBLE)
                    views.setTextViewText(R.id.tv_status_label, "充電中")
                } else {
                    views.setViewVisibility(R.id.img_charging_icon, View.GONE)
                    views.setTextViewText(R.id.tv_status_label, "目前電量")
                }

                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }

                val pendingIntent = PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                appWidgetManager.updateAppWidget(appWidgetId, views)

            } catch (e: Exception) {
                // 即使發生最糟的錯誤，也只會在 Logcat 留下記錄，App 絕對不會閃退
                Log.e("FTESS_Widget", "Widget 更新失敗，已攔截例外", e)
            }
        }
    }
}