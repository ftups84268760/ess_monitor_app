import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/constants.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  // 初始化原生系統推播服務
  // 初始化原生系統推播服務
  static Future<void> init() async {
    try {
      // 🎯 終極修正：加上 @mipmap/ 前綴，並使用您真實的圖示名稱 launcher_icon
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _plugin.initialize(settings: initializationSettings);

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosImplementation = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        await iosImplementation?.requestPermissions(alert: true, badge: true, sound: true);
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidImplementation = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidImplementation?.requestNotificationsPermission();
      }
    } catch (e) {
      // 🎯 核心防護：攔截初始化錯誤，避免 APP 白畫面崩潰
      debugPrint('⚠️ 推播服務初始化失敗 (通常是找不到 Android 圖示): $e');
    }
  }

  // 發送 OS 系統級推播視窗通知核心函數
  static Future<void> showSystemNotification({required String title, required String body}) async {
    if (!GlobalState.isPushNotificationEnabled) return;

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'ess_alert_channel_v2',
      '儲能告警與氣象通知',
      channelDescription: '發送逆變器告警、錯誤訊息與惡劣天氣預報系統通知',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );

    // 🎯 修正：加回所有的具名參數標籤 (id:, title:, body:, notificationDetails:)[cite: 3]
    await _plugin.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
    );
  }
}