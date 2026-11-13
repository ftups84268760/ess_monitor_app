import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Supabase 設定
const String supabaseUrl = 'https://gqrzhpkvspakfqpiqplh.supabase.co';
const String supabaseAnonKey = 'sb_publishable_-xaEf27M-i__nMwA6lneGw_r5THPGRc';

// 中央氣象署開放資料平台 API 授權碼
const String cwaApiKey = 'CWA-DEF98EB1-4274-4AAE-88AD-030F9750AD11';

// 惡劣天氣關鍵字清單
const List<String> kSevereWeatherKeywords = [
  '雷', '雷雨', '大雷雨', '陣雨', '雷陣雨',
  '豪雨', '大雨', '大豪雨', '超大豪雨', '颱風',
];

// 全局狀態管理
class GlobalState {
  static bool isBackupProtectionEnabled = true;
  static bool isPushNotificationEnabled = true;
  static String? lastNotifiedSevereMessage;
}

// ==========================================
// 🎯 跨平台與響應式三態佈局判斷 (Web / 手機寬版 / 手機窄版)
// ==========================================
enum AppLayoutMode {
  web,           // 1. 瀏覽器環境 (網頁版)
  mobileWide,    // 2. 原生 App 且螢幕展開/寬螢幕 (如 iPhone Duo 展開、iPad)
  mobileCompact, // 3. 原生 App 且為一般直向窄螢幕 (一般手機直向)
}

extension LayoutContextExtension on BuildContext {
  /// 取得當前的三態佈局模式：先區分「瀏覽器 vs 手機」，若為手機再以寬度區分「寬版 vs 窄版」
  AppLayoutMode get layoutMode {
    if (kIsWeb) return AppLayoutMode.web;

    final double width = MediaQuery.of(this).size.width;
    // 螢幕寬度大於等於 650 pt 時視為「手機寬版」(涵蓋 iPhone Duo 展開與平板)
    if (width >= 650) {
      return AppLayoutMode.mobileWide;
    }
    return AppLayoutMode.mobileCompact;
  }

  /// 是否為瀏覽器網頁版
  bool get isWebLayout => layoutMode == AppLayoutMode.web;

  /// 是否為手機寬版 (iPhone Duo 展開 / 平板)
  bool get isMobileWideLayout => layoutMode == AppLayoutMode.mobileWide;

  /// 是否為手機一般直向窄版
  bool get isMobileCompactLayout => layoutMode == AppLayoutMode.mobileCompact;

  /// 是否使用「寬螢幕骨架」(左側導覽列 + 右側水平滑動卡片)
  /// 註：網頁版 (web) 與手機寬版 (mobileWide) 皆會回傳 true
  bool get useWideLayout =>
      layoutMode == AppLayoutMode.web || layoutMode == AppLayoutMode.mobileWide;
}