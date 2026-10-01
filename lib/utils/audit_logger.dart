import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 寫入使用者操作紀錄 (Audit Log)
/// [action] 動作類型，例如：'登入', '登出', '權限變更', '刪除設備'
/// [details] 動作細節，例如：'將 test@email.com 升級為管理員'
Future<void> logUserAction(String action, {String details = ''}) async {
  try {
    // 取得目前登入的使用者
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.email == null) return;

    // 將紀錄寫入 Supabase 資料表
    await Supabase.instance.client.from('user_activity_logs').insert({
      'user_email': user.email,
      'action': action,
      'details': details,
    });
  } catch (e) {
    // 寫入失敗不阻斷主流程，僅印出偵錯訊息
    debugPrint('寫入操作紀錄失敗: $e');
  }
}