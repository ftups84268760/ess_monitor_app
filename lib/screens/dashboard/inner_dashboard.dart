import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart'; 
import 'home_screen.dart';
import 'analysis_screen.dart';
import 'data_alarm_screens.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '/services/notification_service.dart';

class InnerDashboardNavigation extends StatefulWidget {
  final String customInverterName;
  final bool isInverterOnline;
  final String deviceDbId;
  final String inverterSn;
  final String accountType;
  final bool isPushedFullScreen;

  const InnerDashboardNavigation({
    super.key,
    required this.customInverterName,
    required this.isInverterOnline,
    required this.deviceDbId,
    required this.inverterSn,
    required this.accountType,
    this.isPushedFullScreen = false,
  });
  @override State<InnerDashboardNavigation> createState() => _InnerDashboardNavigationState();
}

class _InnerDashboardNavigationState extends State<InnerDashboardNavigation> {
  int _currentIndex = 0;
  late Timer _timer;
  String _timeString = '';
  String _lunarString = '';
  
  late bool _isDeviceOnline;
  RealtimeChannel? _deviceChannel;
  StreamSubscription<RemoteMessage>? _fcmSubscription;

  List<Map<String, dynamic>> _notificationList = [];
  int get _unreadCount => _notificationList.where((n) => n['is_read'] == false).length;
  RealtimeChannel? _notificationChannel;

  // 🎯 新增：紀錄當前使用者是否為該設備的擁有者
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _isDeviceOnline = widget.isInverterOnline; 
    
    _updateTimeAndLunar();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTimeAndLunar());
    
    _setupDeviceStatusSubscription();
    _setupForegroundMessaging();
    
    _fetchNotifications();
    _setupNotificationSubscription();

    // 🎯 初始化時檢查設備擁有權
    _checkOwnership();
  }

  // 🎯 新增檢查設備擁有權的非同步函式
  Future<void> _checkOwnership() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      
      final data = await Supabase.instance.client
          .from('devices')
          .select('user_id')
          .eq('id', widget.deviceDbId)
          .maybeSingle();
          
      if (mounted && data != null) {
        setState(() {
          _isOwner = data['user_id'] == user.id;
        });
      }
    } catch (e) {
      debugPrint('確認設備擁有權失敗: $e');
    }
  }

  Future<void> _fetchNotifications() async {
    try {
      final data = await Supabase.instance.client
          .from('device_notifications')
          .select()
          .eq('device_id', widget.inverterSn)
          .order('created_at', ascending: false)
          .limit(50); 
          
      if (mounted) {
        setState(() { _notificationList = List<Map<String, dynamic>>.from(data); });
      }
    } catch (e) {
      debugPrint('讀取通知失敗: $e');
    }
  }

  void _setupNotificationSubscription() {
    _notificationChannel = Supabase.instance.client.channel('public:device_notifications:id=eq.${widget.inverterSn}');
    _notificationChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'device_notifications',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'device_id', value: widget.inverterSn),
      callback: (payload) {
        _fetchNotifications(); 
      },
    ).subscribe();
  }

  void _setupForegroundMessaging() {
    _fcmSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔔 [母框架前景推播] 收到新訊息: ${message.notification?.title}');
      
      if (message.notification != null) {
        NotificationService.showSystemNotification(
          title: message.notification!.title ?? '⚠️ 設備連線狀態通知',
          body: message.notification!.body ?? '您的設備狀態已更新',
        );
        _fetchNotifications();
      }
    });
  }

  void _setupDeviceStatusSubscription() {
    if (widget.deviceDbId.isEmpty) return;
    _deviceChannel = Supabase.instance.client.channel('public:devices_inner:id=eq.${widget.deviceDbId}');
    _deviceChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'devices',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.deviceDbId),
      callback: (payload) {
        if (mounted && payload.newRecord['is_online'] != null) {
          setState(() { _isDeviceOnline = payload.newRecord['is_online'] as bool; });
        }
      },
    ).subscribe();
  }

  @override
  void dispose() { 
    _timer.cancel(); 
    _deviceChannel?.unsubscribe(); 
    _notificationChannel?.unsubscribe(); 
    _fcmSubscription?.cancel(); 
    super.dispose(); 
  }

  String _calculateTaiwanLunar(DateTime date) {
    Lunar lunar = Lunar.fromDate(date);
    return "${lunar.getYearInGanZhi()}年 ${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}";
  }

  void _updateTimeAndLunar() {
    final DateTime now = DateTime.now();
    const List<String> weekDayNames = ['週一', '週二', '週三', '週四', '週五', '週六', '週日'];
    String weekDayStr = weekDayNames[now.weekday - 1];

    setState(() {
      _timeString = "${now.year}/${_twoDigits(now.month)}/${_twoDigits(now.day)} ($weekDayStr) ${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:${_twoDigits(now.second)}";
      _lunarString = _calculateTaiwanLunar(now);
    });
  }
  
  String _twoDigits(int n) => n >= 10 ? "$n" : "0$n";

  Future<void> _markAllAsRead() async {
    // 🎯 修改點：如果是管理員且「不是擁有者」，或是沒有未讀訊息，才中止執行
    if ((widget.accountType == '系統管理員(root)' && !_isOwner) || _unreadCount == 0) return;
    try {
      await Supabase.instance.client
          .from('device_notifications')
          .update({'is_read': true})
          .eq('device_id', widget.inverterSn)
          .eq('is_read', false);
      _fetchNotifications();
    } catch (e) {
      debugPrint('標記已讀失敗: $e');
    }
  }

  Future<void> _clearAllNotifications() async {
    try {
      await Supabase.instance.client
          .from('device_notifications')
          .delete()
          .eq('device_id', widget.inverterSn);
      _fetchNotifications();
      if (mounted) Navigator.pop(context); 
    } catch (e) {
      debugPrint('清空通知失敗: $e');
    }
  }

  void _showNotificationSheet() {
    _markAllAsRead(); 
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder( 
          builder: (BuildContext context, StateSetter setSheetState) {
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('系統通知', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                        // 🎯 修改點：增加 || _isOwner 判斷，讓身兼管理員與擁有者的帳號可以看到清除按鈕
                        if (_notificationList.isNotEmpty && (widget.accountType != '系統管理員(root)' || _isOwner))
                          TextButton(
                            onPressed: _clearAllNotifications,
                            child: const Text('全部清除', style: TextStyle(color: Colors.redAccent)),
                          )
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _notificationList.isEmpty
                        ? const Center(
                            child: Text('目前沒有任何通知', style: TextStyle(color: Colors.black38, fontSize: 15)),
                          )
                        : ListView.separated(
                            itemCount: _notificationList.length,
                            separatorBuilder: (context, index) => const Divider(height: 1, indent: 20, endIndent: 20),
                            itemBuilder: (context, index) {
                              final noti = _notificationList[index];
                              final time = DateTime.parse(noti['created_at'].toString()).toLocal();
                              final timeStr = "${time.month}/${time.day} ${_twoDigits(time.hour)}:${_twoDigits(time.minute)}";
                              
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.teal.withValues(alpha: 0.1),
                                  child: const Icon(Icons.notifications_active, color: Colors.teal, size: 20),
                                ),
                                title: Text(noti['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(noti['message'] ?? '', style: const TextStyle(color: Colors.black87, fontSize: 13)),
                                ),
                                trailing: Text(timeStr, style: const TextStyle(color: Colors.black38, fontSize: 11)),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isWideScreen = MediaQuery.of(context).size.width > 800;

    // 🎯 核心防護：如果這個畫面是被全螢幕推出來的，且現在視窗被拉寬了，就自動退回底層的後台選單
    if (widget.isPushedFullScreen && isWideScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          // 🎯 這裡加上 'resize' 標記，讓設備清單知道它是因為螢幕變寬而退場的
          Navigator.pop(context, 'resize'); 
        }
      });
    }
    
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 0) {
          setState(() { _currentIndex = 0; });
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.white,
        appBar: AppBar(
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent, 
            statusBarIconBrightness: Brightness.dark, 
            statusBarBrightness: Brightness.light,    
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.customInverterName,
                    style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _isDeviceOnline ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isDeviceOnline ? Colors.green : Colors.red).withValues(alpha: 0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        )
                      ],
                    ),
                  ),
                ],
              ),
              Text(
                'SN: ${widget.inverterSn}',
                style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          // 🎯 需求 1 解決：只在窄螢幕 (手機版) 顯示返回鍵
          leading: MediaQuery.of(context).size.width > 800
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87),
                  onPressed: () {
                    if (_currentIndex != 0) {
                      setState(() { _currentIndex = 0; });
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
          actions: [
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_none, color: Colors.black87, size: 26),
                  onPressed: _showNotificationSheet,
                ),
                if (_unreadCount > 0)
                  Positioned(
                    right: 8,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, height: 1.1),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            HomeScreen(
              timeString: _timeString,
              lunarString: _lunarString,
              deviceDbId: widget.deviceDbId,
              customInverterName: widget.customInverterName,
              isDeviceOnline: _isDeviceOnline, 
              accountType: widget.accountType,
              inverterSn: widget.inverterSn,
            ),
            SafeArea(child: AnalysisScreen(deviceDbId: widget.deviceDbId)),
            SafeArea(child: RawDataScreen(deviceDbId: widget.deviceDbId)),
            SafeArea(child: AlarmListScreen(deviceDbId: widget.deviceDbId))
          ]
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: Colors.teal,
          unselectedItemColor: Colors.black38,
          currentIndex: _currentIndex,
          onTap: (index) { setState(() { _currentIndex = index; }); },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.bolt, size: 16), label: '總覽'),
            BottomNavigationBarItem(icon: Icon(Icons.analytics, size: 16), label: '分析'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart, size: 16), label: '數據'),
            BottomNavigationBarItem(icon: Icon(Icons.warning_amber_rounded, size: 16), label: '告警')
          ],
        ),
      ),
    );
  }
}