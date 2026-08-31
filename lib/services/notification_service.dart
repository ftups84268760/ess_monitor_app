import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/constants.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  // 初始化原生系統推播服務
  static Future<void> init() async {
    // 🎯 核心修正：將 '@mipmap/ic_launcher' 更改為 'ic_launcher'
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // 🎯 修正：加回 settings: 標籤[cite: 3]
    await _plugin.initialize(settings: initializationSettings);

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosImplementation = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      await iosImplementation?.requestPermissions(alert: true, badge: true, sound: true);
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.requestNotificationsPermission();
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