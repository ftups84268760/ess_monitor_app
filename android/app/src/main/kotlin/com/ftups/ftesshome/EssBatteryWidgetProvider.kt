package com.ftups.ftesshome

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class EssBatteryWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            // 1. 取得從 Flutter 傳來的資料 (透過 home_widget 套件)
            val widgetData = HomeWidgetPlugin.getData(context)
            val soc = widgetData.getInt("battery_soc", 0)
            val deviceName = widgetData.getString("device_name", "載入中...")
            val isCharging = widgetData.getBoolean("is_charging", false)

            // 2. 綁定我們的 XML 佈局
            val views = RemoteViews(context.packageName, R.layout.widget_ess_battery)

            // 3. 更新文字
            views.setTextViewText(R.id.tv_device_name, deviceName)
            views.setTextViewText(R.id.tv_soc, "$soc%")

            // 4. 更新電池動態液面 (ClipDrawable 的 level 是 0~10000)
            // 使用 maxOf 確保電量極低時，依然會顯示一點點液面高度
            val fillLevel = maxOf(soc * 100, 500)
            views.setInt(R.id.img_battery_fill, "setImageLevel", fillLevel)

            // 5. 同步更新水平漸層進度條
            views.setProgressBar(R.id.pb_soc, 100, soc, false)

            // 6. 控制充電閃電圖示的顯示與隱藏
            views.setViewVisibility(
                R.id.img_charging_icon,
                if (isCharging) View.VISIBLE else View.GONE
            )

            // 7. 設定點擊 Widget (widget_root) 喚醒 APP
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    appWidgetId, // 使用 appWidgetId 作為 RequestCode 避免多個 Widget 衝突
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            // 8. 通知系統更新這個 Widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}