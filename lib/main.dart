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

  // 🎯 優化：加入 try-catch 與 timeout，避免無網路時開機卡死
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
    await Future.delayed(const Duration(milliseconds: 2200));

    final prefs = await SharedPreferences.getInstance();
    final bool autoLogin = prefs.getBool('auto_login') ?? false;
    final session = Supabase.instance.client.auth.currentSession;

    if (autoLogin && session != null) {
      GlobalState.isPushNotificationEnabled = prefs.getBool('push_notifications_enabled') ?? true;
      GlobalState.isBackupProtectionEnabled = prefs.getBool('backup_protection_enabled') ?? true;
      
      await _setupAndUploadFcmToken();
      
      if (mounted) {
        setState(() {
          _isLoggedIn = true;
          _showSplash = false;
        });
      }
    } else {
      if (autoLogin && session == null) {
        debugPrint('⚠️ 偵測到 Session 逾時登出，強制銷毀本地推播 Token');
        await FirebaseMessaging.instance.deleteToken();
        await prefs.setBool('auto_login', false); 
        
      } else if (!autoLogin && session != null) {
        await Supabase.instance.client.auth.signOut();
        await FirebaseMessaging.instance.deleteToken();
      }

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
                  Text('智慧儲能控制中心', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_isLoggedIn) {
      return MainNavigationScreen(onLogout: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('auto_login', false);
        
        await FirebaseMessaging.instance.deleteToken();
        await Supabase.instance.client.auth.signOut();
        
        setState(() {
          _isLoggedIn = false;
        });
      });
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