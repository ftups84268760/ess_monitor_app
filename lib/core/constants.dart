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