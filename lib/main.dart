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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Supabase.initialize(
      url: supabaseUrl, 
      publishableKey: supabaseAnonKey,
    ).timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('Supabase 初始化超時或無網路連線: $e');
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
          debugPrint('✅ FCM Token 註冊並上傳成功: $fcmToken');
        }

        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          final currentUserId = Supabase.instance.client.auth.currentUser?.id;
          if (currentUserId != null) {
            await Supabase.instance.client
                .from('profiles')
                .update({'fcm_token': newToken})
                .eq('id', currentUserId);
            debugPrint('🔄 FCM Token 已自動刷新並更新至資料庫');
          }
        });
      } else {
        debugPrint('⚠️ 使用者拒絕了推播通知權限');
      }
    } catch (e) {
      debugPrint('❌ 設定 FCM Token 發生錯誤: $e');
    }
  }

  Future<void> _initializeAppAndCheckLogin() async {
    if (!kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 2200));
    } else {
      // 🎯 給予網頁版 1.2 秒的延遲，用來完美展示 0~100% 動態進度條
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
            debugPrint('⚠️ 權限不足：非 root 管理員嘗試登入網頁版');
            await Supabase.instance.client.auth.signOut();
            await prefs.setBool('auto_login', false);
            session = null; 
          }
        } catch (e) {
          debugPrint('讀取權限失敗，基於安全考量強制登出: $e');
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
          debugPrint('⚠️ 偵測到 Session 逾時登出或權限不足，強制銷毀本地推播 Token');
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
      // 🎯 分流：網頁版顯示進度條，手機版顯示背景圖
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
                    duration: const Duration(milliseconds: 1200), // 配合延遲時間
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
      return ResponsiveLayout(
        mobileApp: MainNavigationScreen(onLogout: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('auto_login', false);
          
          await FirebaseMessaging.instance.deleteToken();
          await Supabase.instance.client.auth.signOut();
          
          setState(() {
            _isLoggedIn = false;
          });
        }),
        webAdmin: const WebAdminScreen(), 
      );
    } else {
      return LoginScreen(onLoginSuccess: () {
        _setupAndUploadFcmToken();
        
        setState(() {
          _isLoggedIn = true;
        });
      });
    }
  }
}