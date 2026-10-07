import 'dart:async';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart'; 
import 'package:url_launcher/url_launcher.dart'; 
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

class _InnerDashboardNavigationState extends State<InnerDashboardNavigation> with WidgetsBindingObserver {
  int _currentIndex = 0;
  
  String _timeString = '';
  String _lunarString = '';
  
  late bool _isDeviceOnline;
  RealtimeChannel? _deviceChannel;
  StreamSubscription<RemoteMessage>? _fcmSubscription;

  List<Map<String, dynamic>> _notificationList = [];
  RealtimeChannel? _notificationChannel;
  RealtimeChannel? _readReceiptsChannel;

  List<Map<String, dynamic>> _broadcastList = [];

  bool _isOwner = false;

  int _unreadSystemCount = 0;
  int _unreadBroadcastCount = 0;
  
  List<String> _readBroadcastIds = [];
  
  int get _totalUnreadCount => _unreadSystemCount + _unreadBroadcastCount;

  bool get _isAdminObserver => widget.accountType.contains('管理員') && !_isOwner;

  Map<String, dynamic>? _selectedDetailItem;
  bool _isSelectedItemBroadcast = false;

  int _currentTabIndex = 0;

  StateSetter? _sheetSetState;
  
  bool _isBottomSheetOpen = false;
  StreamSubscription<AuthState>? _authStateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    
    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        if (_isBottomSheetOpen && mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          _isBottomSheetOpen = false;
        }
      }
    });
    
    _isDeviceOnline = widget.isInverterOnline; 
    _updateTimeAndLunar(); 
    
    _setupDeviceStatusSubscription();
    _setupForegroundMessaging();
    
    _fetchCloudReadBroadcasts().then((_) {
      _fetchNotifications();
      _fetchBroadcasts(); 
    });
    
    _setupNotificationSubscription();
    _checkOwnership();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateTimeAndLunar();
    }
  }

  Future<void> _fetchCloudReadBroadcasts() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final res = await Supabase.instance.client
          .from('user_broadcast_reads')
          .select('broadcast_id')
          .eq('user_id', userId);
      if (mounted) {
        _readBroadcastIds = (res as List).map((e) => e['broadcast_id'].toString()).toList();
        _updateUnreadCounts();
      }
    } catch (e) {
      debugPrint('讀取雲端已讀紀錄失敗: $e');
    }
  }

  void _updateUnreadCounts() {
    _unreadSystemCount = _notificationList.where((n) => n['is_read'] == false).length;
    _unreadBroadcastCount = _broadcastList.where((b) => !_readBroadcastIds.contains(b['id'].toString())).length;
  }

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
        setState(() { 
          _notificationList = List<Map<String, dynamic>>.from(data); 
          _updateUnreadCounts(); 
        });
        _sheetSetState?.call(() {});
      }
    } catch (e) {
      debugPrint('讀取通知失敗: $e');
    }
  }

  Future<void> _fetchBroadcasts() async {
    try {
      final data = await Supabase.instance.client
          .from('system_broadcasts') 
          .select()
          .order('created_at', ascending: false)
          .limit(20);
          
      if (mounted) {
        setState(() { 
          _broadcastList = List<Map<String, dynamic>>.from(data); 
          _updateUnreadCounts(); 
        });
        _sheetSetState?.call(() {});
      }
    } catch (e) {
      try {
        final data = await Supabase.instance.client
            .from('device_notifications')
            .select()
            .eq('device_id', 'BROADCAST')
            .order('created_at', ascending: false)
            .limit(20);
        if (mounted) {
          setState(() { 
            _broadcastList = List<Map<String, dynamic>>.from(data); 
            _updateUnreadCounts(); 
          });
          _sheetSetState?.call(() {});
        }
      } catch (_) {}
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

    Supabase.instance.client.channel('public:system_broadcasts_updates')
      .onPostgresChanges(
        event: PostgresChangeEvent.all, // 🎯 關鍵修改：從 insert 改為 all，這樣新增、修改、刪除都會觸發更新
        schema: 'public',
        table: 'system_broadcasts',
        callback: (payload) { _fetchBroadcasts(); }
      ).subscribe();

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      _readReceiptsChannel = Supabase.instance.client.channel('public:user_broadcast_reads_updates:user_id=eq.$userId');
      _readReceiptsChannel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'user_broadcast_reads',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
        callback: (payload) {
          if (mounted) {
            final newReadId = payload.newRecord['broadcast_id'].toString();
            if (!_readBroadcastIds.contains(newReadId)) {
              setState(() {
                _readBroadcastIds.add(newReadId);
                _updateUnreadCounts();
              });
              _sheetSetState?.call(() {});
            }
          }
        }
      ).subscribe();
    }
  }

  void _setupForegroundMessaging() {
    _fcmSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        NotificationService.showSystemNotification(
          title: message.notification!.title ?? '⚠️ 設備連線狀態通知',
          body: message.notification!.body ?? '您的設備狀態已更新',
        );
        _fetchNotifications();
        _fetchBroadcasts(); 
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
    WidgetsBinding.instance.removeObserver(this);
    _authStateSubscription?.cancel(); 
    _deviceChannel?.unsubscribe(); 
    _notificationChannel?.unsubscribe(); 
    _readReceiptsChannel?.unsubscribe(); 
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
      _timeString = "${now.year}/${_twoDigits(now.month)}/${_twoDigits(now.day)} ($weekDayStr) ${_twoDigits(now.hour)}:${_twoDigits(now.minute)}";
      _lunarString = _calculateTaiwanLunar(now);
    });
  }
  
  String _twoDigits(int n) => n >= 10 ? "$n" : "0$n";

  Future<void> _markAllSystemAsRead(StateSetter setSheetState) async {
    if (_isAdminObserver || _unreadSystemCount == 0) return;
    try {
      await Supabase.instance.client
          .from('device_notifications')
          .update({'is_read': true})
          .eq('device_id', widget.inverterSn)
          .eq('is_read', false);
      await _fetchNotifications();
      setSheetState((){}); 
    } catch (e) {
      debugPrint('標記系統通知已讀失敗: $e');
    }
  }

  Future<void> _clearAllSystemNotifications(StateSetter setSheetState) async {
    if (_isAdminObserver) return;
    try {
      await Supabase.instance.client
          .from('device_notifications')
          .delete()
          .eq('device_id', widget.inverterSn);
      await _fetchNotifications();
      setSheetState((){}); 
    } catch (e) {
      debugPrint('清空通知失敗: $e');
    }
  }

  Future<void> _markAllBroadcastAsRead(StateSetter setSheetState) async {
    if (_isAdminObserver || _unreadBroadcastCount == 0 || _broadcastList.isEmpty) return;
    
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    List<Map<String, dynamic>> inserts = [];

    for (var b in _broadcastList) {
      final bId = b['id'].toString();
      if (!_readBroadcastIds.contains(bId)) {
        _readBroadcastIds.add(bId);
        inserts.add({
          'user_id': userId,
          'broadcast_id': bId,
        });
      }
    }

    setState(() { _updateUnreadCounts(); });
    setSheetState((){});

    if (inserts.isNotEmpty) {
      try {
        await Supabase.instance.client.from('user_broadcast_reads').upsert(inserts);
      } catch (e) {
        debugPrint('雲端同步已讀狀態失敗: $e');
      }
    }
  }

  Widget _buildMessageWithLinks(String text) {
    final urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final Iterable<RegExpMatch> matches = urlRegExp.allMatches(text);

    if (matches.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.6));
    }

    List<TextSpan> spans = [];
    int lastMatchEnd = 0;

    for (var match in matches) {
      final String url = match.group(0)!;
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: url,
          style: const TextStyle(color: Colors.blueAccent, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()..onTap = () async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
      );
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.6),
        children: spans,
      ),
    );
  }

  void _showNotificationSheet() {
    _selectedDetailItem = null; 
    _currentTabIndex = 0; 
    _isBottomSheetOpen = true; 
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, 
      barrierColor: Colors.black.withValues(alpha: 0.25), 
      isScrollControlled: true, 
      builder: (context) {
        return StatefulBuilder( 
          builder: (BuildContext context, StateSetter setSheetState) {
            
            _sheetSetState = setSheetState;
            
            if (_selectedDetailItem != null) {
              final time = DateTime.parse(_selectedDetailItem!['created_at'].toString()).toLocal();
              final fullTimeStr = "${time.year}/${_twoDigits(time.month)}/${_twoDigits(time.day)} ${_twoDigits(time.hour)}:${_twoDigits(time.minute)}:${_twoDigits(time.second)}";
              
              return FractionallySizedBox(
                heightFactor: 0.70, 
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), 
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85), 
                        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.6), width: 1.5))
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 16, 4),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
                                  onPressed: () => setSheetState(() => _selectedDetailItem = null),
                                ),
                                const Spacer(),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(fullTimeStr, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(_selectedDetailItem!['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: (_isSelectedItemBroadcast ? Colors.orange : Colors.teal).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(12)
                                        ),
                                        child: Icon(_isSelectedItemBroadcast ? Icons.campaign_rounded : Icons.notifications_active, color: _isSelectedItemBroadcast ? Colors.orange : Colors.teal, size: 28),
                                      )
                                    ],
                                  ),
                                  const Divider(height: 32, color: Colors.black12),
                                  _buildMessageWithLinks(_selectedDetailItem!['message'] ?? ''),
                                  const SizedBox(height: 40),
                                ],
                              ),
                            ),
                          )
                        ]
                      ),
                    ),
                  ),
                ),
              );
            }

            return FractionallySizedBox(
              heightFactor: 0.70, 
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), 
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.65), 
                      border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.6), width: 1.5))
                    ),
                    child: DefaultTabController(
                      length: 2,
                      initialIndex: _currentTabIndex, 
                      child: Builder( 
                        builder: (context) {
                          final tabController = DefaultTabController.of(context);
                          tabController.addListener(() {
                            if (!tabController.indexIsChanging) {
                              _currentTabIndex = tabController.index; 
                            }
                          });

                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('訊息通知', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, color: Colors.black45),
                                      onPressed: () => Navigator.pop(context),
                                    )
                                  ],
                                ),
                              ),
                              
                              TabBar(
                                indicatorColor: Colors.teal,
                                labelColor: Colors.teal,
                                unselectedLabelColor: Colors.black54,
                                labelPadding: EdgeInsets.zero,
                                tabs: [
                                  Tab(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text('系統通知', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        if (_unreadSystemCount > 0) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                            child: Text('$_unreadSystemCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1.1)),
                                          ),
                                        ]
                                      ],
                                    ),
                                  ),
                                  Tab(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text('官方公告', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        if (_unreadBroadcastCount > 0) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                            child: Text('$_unreadBroadcastCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1.1)),
                                          ),
                                        ]
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 1, color: Colors.black12),
                              
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    Column(
                                      children: [
                                        if (_notificationList.isNotEmpty && !_isAdminObserver) 
                                          Padding(
                                            padding: const EdgeInsets.only(right: 12.0, top: 4.0),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                TextButton.icon(
                                                  icon: const Icon(Icons.checklist_rounded, size: 16),
                                                  label: const Text('全部已讀', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                                  onPressed: () => _markAllSystemAsRead(setSheetState),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: Colors.teal,
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // 🎯 修改：全部刪除按鈕加入 AlertDialog 確認視窗
                                                TextButton.icon(
                                                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                                  label: const Text('全部刪除', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                                  onPressed: () {
                                                    showDialog(
                                                      context: context,
                                                      builder: (BuildContext dialogContext) {
                                                        return AlertDialog(
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                          title: const Row(
                                                            children: [
                                                              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                                                              SizedBox(width: 8),
                                                              Text('刪除確認', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                                            ],
                                                          ),
                                                          content: const Text('確定要刪除所有系統通知嗎？\n此操作無法復原。', style: TextStyle(fontSize: 14, height: 1.5)),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.pop(dialogContext),
                                                              child: const Text('取消', style: TextStyle(color: Colors.grey)),
                                                            ),
                                                            ElevatedButton(
                                                              style: ElevatedButton.styleFrom(
                                                                backgroundColor: Colors.redAccent,
                                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                                elevation: 0,
                                                              ),
                                                              onPressed: () {
                                                                Navigator.pop(dialogContext);
                                                                _clearAllSystemNotifications(setSheetState);
                                                              },
                                                              child: const Text('確定', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                            ),
                                                          ],
                                                        );
                                                      },
                                                    );
                                                  },
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: Colors.redAccent,
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        Expanded(
                                          child: _notificationList.isEmpty
                                              ? const Center(child: Text('目前沒有任何系統通知', style: TextStyle(color: Colors.black38, fontSize: 14)))
                                              : ListView.separated(
                                                  itemCount: _notificationList.length,
                                                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 20, endIndent: 20, color: Colors.black12),
                                                  itemBuilder: (context, index) {
                                                    final noti = _notificationList[index];
                                                    final time = DateTime.parse(noti['created_at'].toString()).toLocal();
                                                    final timeStr = "${time.month}/${time.day} ${_twoDigits(time.hour)}:${_twoDigits(time.minute)}";
                                                    
                                                    final bool isUnread = noti['is_read'] == false;
                                                    
                                                    String msgText = (noti['message'] ?? '').replaceAll('\n', ' ');
                                                    if (msgText.length > 35) {
                                                      msgText = '${msgText.substring(0, 35)} >>';
                                                    }

                                                    return ListTile(
                                                      tileColor: isUnread ? Colors.teal.withValues(alpha: 0.05) : Colors.transparent,
                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                                      leading: CircleAvatar(
                                                        backgroundColor: isUnread ? Colors.teal.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05),
                                                        child: Icon(Icons.notifications_active, color: isUnread ? Colors.teal : Colors.black38, size: 20),
                                                      ),
                                                      title: Text(noti['title'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isUnread ? Colors.black87 : Colors.black54)),
                                                      subtitle: Padding(
                                                        padding: const EdgeInsets.only(top: 4.0),
                                                        child: Text(msgText, style: TextStyle(color: isUnread ? Colors.black54 : Colors.black38, fontSize: 13, height: 1.4)),
                                                      ),
                                                      trailing: Text(timeStr, style: const TextStyle(color: Colors.black38, fontSize: 11)),
                                                      onTap: () async {
                                                        if (isUnread && !_isAdminObserver) {
                                                          await Supabase.instance.client.from('device_notifications').update({'is_read': true}).eq('id', noti['id']);
                                                          setState(() {
                                                            noti['is_read'] = true;
                                                            _updateUnreadCounts();
                                                          });
                                                        }
                                                        setSheetState(() {
                                                          _selectedDetailItem = noti;
                                                          _isSelectedItemBroadcast = false;
                                                        });
                                                      },
                                                    );
                                                  },
                                                ),
                                        ),
                                      ],
                                    ),

                                    Column(
                                      children: [
                                        if (_broadcastList.isNotEmpty && !_isAdminObserver) 
                                          Padding(
                                            padding: const EdgeInsets.only(right: 12.0, top: 4.0),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                TextButton.icon(
                                                  icon: const Icon(Icons.checklist_rounded, size: 16),
                                                  label: const Text('全部已讀', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                                  onPressed: () => _markAllBroadcastAsRead(setSheetState),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: Colors.teal,
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        Expanded(
                                          child: _broadcastList.isEmpty
                                            ? const Center(child: Text('目前沒有官方公告', style: TextStyle(color: Colors.black38, fontSize: 14)))
                                            : ListView.separated(
                                                itemCount: _broadcastList.length,
                                                separatorBuilder: (context, index) => const Divider(height: 1, indent: 20, endIndent: 20, color: Colors.black12),
                                                itemBuilder: (context, index) {
                                                  final noti = _broadcastList[index];
                                                  final time = DateTime.parse(noti['created_at'].toString()).toLocal();
                                                  final timeStr = "${time.month}/${time.day} ${_twoDigits(time.hour)}:${_twoDigits(time.minute)}";
                                                  
                                                  final bool isUnread = !_readBroadcastIds.contains(noti['id'].toString());

                                                  String msgText = (noti['message'] ?? '').replaceAll('\n', ' ');
                                                  if (msgText.length > 35) {
                                                    msgText = '${msgText.substring(0, 35)} >>';
                                                  }

                                                  return ListTile(
                                                    tileColor: isUnread ? Colors.orange.withValues(alpha: 0.05) : Colors.transparent,
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                                    leading: CircleAvatar(
                                                      backgroundColor: isUnread ? Colors.orange.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05),
                                                      child: Icon(Icons.campaign_rounded, color: isUnread ? Colors.orange : Colors.black38, size: 22),
                                                    ),
                                                    title: Text(noti['title'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isUnread ? Colors.black87 : Colors.black54)),
                                                    subtitle: Padding(
                                                      padding: const EdgeInsets.only(top: 6.0),
                                                      child: Text(msgText, style: TextStyle(color: isUnread ? Colors.black54 : Colors.black38, fontSize: 14, height: 1.5)),
                                                    ),
                                                    trailing: Text(timeStr, style: const TextStyle(color: Colors.black38, fontSize: 11)),
                                                    onTap: () async {
                                                      if (isUnread && !_isAdminObserver) {
                                                        final bId = noti['id'].toString();
                                                        _readBroadcastIds.add(bId);
                                                        setState(() { _updateUnreadCounts(); });
                                                        
                                                        final userId = Supabase.instance.client.auth.currentUser?.id;
                                                        if (userId != null) {
                                                          Supabase.instance.client.from('user_broadcast_reads').upsert({
                                                            'user_id': userId,
                                                            'broadcast_id': bId,
                                                          }).catchError((e) => debugPrint('雲端同步單筆已讀失敗: $e'));
                                                        }
                                                      }
                                                      setSheetState(() {
                                                        _selectedDetailItem = noti;
                                                        _isSelectedItemBroadcast = true;
                                                      });
                                                    },
                                                  );
                                                },
                                              ),
                                        ),
                                      ]
                                    )
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        );
      }
    ).whenComplete(() {
      _sheetSetState = null;
      _isBottomSheetOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isWideScreen = MediaQuery.of(context).size.width > 800;

    if (widget.isPushedFullScreen && isWideScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
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
                if (_totalUnreadCount > 0)
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
                        _totalUnreadCount > 99 ? '99+' : '$_totalUnreadCount',
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
            SafeArea(child: RawDataScreen(deviceDbId: widget.deviceDbId, inverterSn: widget.inverterSn)),
            SafeArea(child: AlarmListScreen(deviceDbId: widget.deviceDbId, inverterSn: widget.inverterSn))
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