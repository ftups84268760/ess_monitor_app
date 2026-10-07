import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/constants.dart';
import 'services/notification_service.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/main_navigation_screen.dart';

import 'widgets/responsive_layout.dart';
import 'screens/web_admin_screen.dart';
import 'package:flutter/foundation.dart'; 

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; 
import 'package:home_widget/home_widget.dart';
import 'widgets/web_session_timeout_listener.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 🎯 修正 1：必須傳入 options，否則 Android 背景 Isolate 會直接閃退崩潰
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ); 

  if (message.data['type'] == 'widget_sync') {
    try {
      final int soc = int.tryParse(message.data['soc']?.toString() ?? '0') ?? 0;
      final bool isCharging = (message.data['is_charging']?.toString() == 'true');
      final String deviceName = message.data['device_name']?.toString() ?? '未知設備';
      final double updateTime = double.tryParse(message.data['update_time']?.toString() ?? '') 
          ?? (DateTime.now().millisecondsSinceEpoch / 1000.0);

      // 🎯 修正 2：App Group 僅限 iOS，避免 Android 資料庫被寫入錯誤的檔案
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        const String appGroupId = 'group.com.flighttechnic.ftess';
        await HomeWidget.setAppGroupId(appGroupId);
      }

      await HomeWidget.saveWidgetData<int>('battery_soc', soc);
      await HomeWidget.saveWidgetData<bool>('is_charging', isCharging);
      await HomeWidget.saveWidgetData<String>('device_name', deviceName);
      await HomeWidget.saveWidgetData<double>('last_update_timestamp', updateTime);

      await HomeWidget.updateWidget(
        iOSName: 'EssBatteryWidget', 
        androidName: 'EssBatteryWidgetProvider', 
      );

      debugPrint('✅ [靜默推播攔截] Widget 已成功在背景更新: $soc%, 充電中: $isCharging');
    } catch (e) {
      debugPrint('❌ [靜默推播攔截失敗]: $e');
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    // 🎯 修正 3：移除 .timeout(5s)。Supabase 初始化僅需讀取本地 Disk，不應受網路或背景喚醒延遲影響
    await Supabase.initialize(
      url: supabaseUrl, 
      publishableKey: supabaseAnonKey,
    );
  } catch (e) {
    debugPrint('Supabase 初始化失敗: $e');
  }

  await NotificationService.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  bool _isLoggedIn = false;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _initializeAppAndCheckLogin();
  }

  Future<void> _setupAndUploadFcmToken() async {
    try {
      NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        final String? fcmToken = await FirebaseMessaging.instance.getToken();
        final String? userId = Supabase.instance.client.auth.currentUser?.id;

        if (fcmToken != null && userId != null) {
          await Supabase.instance.client
              .from('profiles')
              .update({'fcm_token': fcmToken})
              .eq('id', userId);
        }

        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          final currentUserId = Supabase.instance.client.auth.currentUser?.id;
          if (currentUserId != null) {
            await Supabase.instance.client
                .from('profiles')
                .update({'fcm_token': newToken})
                .eq('id', currentUserId);
          }
        });
      }
    } catch (e) {
      debugPrint('❌ 設定 FCM Token 發生錯誤: $e');
    }
  }

  Future<void> _initializeAppAndCheckLogin() async {
    if (!kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 2200));
    } else {
      await Future.delayed(const Duration(milliseconds: 1200));
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final bool autoLogin = prefs.getBool('auto_login') ?? false;
      var session = Supabase.instance.client.auth.currentSession;

      if (kIsWeb && session != null) {
        try {
          final userData = await Supabase.instance.client
              .from('profiles') 
              .select('role')
              .eq('id', session.user.id)
              .maybeSingle();

          final String userRole = userData?['role'] ?? '';

          if (userRole != '系統管理員(root)') {
            await Supabase.instance.client.auth.signOut();
            await prefs.setBool('auto_login', false);
            session = null; 
          }
        } catch (e) {
          await Supabase.instance.client.auth.signOut();
          session = null;
        }
      }

      if (autoLogin && session != null) {
        GlobalState.isPushNotificationEnabled = prefs.getBool('push_notifications_enabled') ?? true;
        GlobalState.isBackupProtectionEnabled = prefs.getBool('backup_protection_enabled') ?? true;
        
        if (!kIsWeb) {
          try {
            await _setupAndUploadFcmToken();
            await FirebaseMessaging.instance.subscribeToTopic('system_broadcast');
          } catch (e) {
            debugPrint('FCM Token 處理失敗: $e');
          }
        }
        
        if (mounted) {
          setState(() {
            _isLoggedIn = true;
            _showSplash = false; 
          });
        }
      } else {
        if (autoLogin && session == null) {
          if (!kIsWeb) {
            try { await FirebaseMessaging.instance.deleteToken(); } catch (_) {}
          }
          await prefs.setBool('auto_login', false); 
          
        } else if (!autoLogin && session != null) {
          await Supabase.instance.client.auth.signOut();
          if (!kIsWeb) {
            try { await FirebaseMessaging.instance.deleteToken(); } catch (_) {}
          }
        }

        if (mounted) {
          setState(() {
            _isLoggedIn = false;
            _showSplash = false; 
          });
        }
      }
    } catch (e) {
      debugPrint('初始化發生嚴重錯誤: $e');
      if (mounted) {
        setState(() {
          _isLoggedIn = false; 
          _showSplash = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      if (kIsWeb) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.bolt_rounded, size: 64, color: Colors.tealAccent),
                const SizedBox(height: 16),
                const Text('FTESS Home', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 8),
                const Text('管理後台載入中', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 40),
                SizedBox(
                  width: 300,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 1200),
                    builder: (context, value, _) {
                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: value,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${(value * 100).toInt()}%',
                            style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        return Scaffold(
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
            ),
            child: Image.asset(
              'assets/splash_bg.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt_rounded, size: 64, color: Colors.tealAccent),
                    SizedBox(height: 16),
                    Text('FTESS Home', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    if (_isLoggedIn) {
      // 🎯 用我們剛寫好的監聽器包覆整個已登入的畫面
      return WebSessionTimeoutListener(
        duration: const Duration(minutes: 5),
        onTimeout: () async {
          // 1. 先執行非同步任務
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('auto_login', false);
          await Supabase.instance.client.auth.signOut();
          
          // 2. 判斷 State 是否還活著，來更新狀態
          if (!mounted) return;
          setState(() {
            _isLoggedIn = false;
          });

          // 3. 🎯 關鍵修正：判斷 Context 是否還活著，再來顯示 SnackBar
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('您已閒置超過一段時間，系統已自動登出'),
              backgroundColor: Colors.orange,
            ),
          );
        },
        child: ResponsiveLayout(
          mobileApp: MainNavigationScreen(onLogout: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('auto_login', false);
            
            if (!kIsWeb) {
              try { await FirebaseMessaging.instance.deleteToken(); } catch (_) {}
            }
            await Supabase.instance.client.auth.signOut();
            
            setState(() {
              _isLoggedIn = false;
            });
          }),
          webAdmin: const WebAdminScreen(), 
        ),
      );
    }
    else {
      return LoginScreen(onLoginSuccess: () {
        _setupAndUploadFcmToken();
        
        setState(() {
          _isLoggedIn = true;
        });
      });
    }
  }
}