import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../widgets/weather_renderer.dart';
import 'device_list_screen.dart';
import 'profile_screen.dart';
import 'settings_screens.dart'; // 🎯 新增：引入系統設定主選單，供左側導覽列直接推入右側區域

// 🎯 路由深度與設定頁狀態監聽器：
// 1. 偵測是否已從「設備列表」進入逆變器畫面 (isSubPage)
// 2. 偵測目前是否正停留在該逆變器的「設定」或其子頁面中 (isSettingsActive)
class _SubNavObserver extends NavigatorObserver {
  final void Function(bool isSubPage, bool isSettingsActive) onStateChanged;
  final List<Route<dynamic>> _routes = [];

  _SubNavObserver({required this.onStateChanged});

  void _notify() {
    final bool isSubPage = _routes.length > 1;
    // 只要路由堆疊中包含 'device_settings'，代表目前正在檢視該逆變器的「設定」或設定子頁面
    final bool isSettingsActive = _routes.any((r) => r.settings.name == 'device_settings');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onStateChanged(isSubPage, isSettingsActive);
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _notify();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _notify();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _notify();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      final idx = _routes.indexOf(oldRoute);
      if (idx != -1 && newRoute != null) {
        _routes[idx] = newRoute;
      } else {
        _routes.remove(oldRoute);
        if (newRoute != null) _routes.add(newRoute);
      }
    }
    _notify();
  }
}

class MainNavigationScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  const MainNavigationScreen({super.key, required this.onLogout});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  String _globalNickname = '載入中...';
  String _globalRole = '一般使用者';
  String _globalEmail = '';
  String? _globalAvatarUrl;
  bool _isGlobalProfileLoading = true;

  // 🎯 紀錄「監控區」是否已進入特定逆變器，以及是否正打開該逆變器的「設定」頁
  bool _isInMonitorSubPage = false;
  bool _isInDeviceSettings = false;
  bool _isInProfileSubPage = false;
  late final _SubNavObserver _monitorNavObserver;
  late final _SubNavObserver _profileNavObserver;

  final GlobalKey<NavigatorState> _monitorNavigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _profileNavigatorKey = GlobalKey<NavigatorState>();

  static const double _sidebarWidth = 240.0;

  @override
  void initState() {
    super.initState();
    _monitorNavObserver = _SubNavObserver(
      onStateChanged: (inSubPage, inSettings) {
        if (mounted && (_isInMonitorSubPage != inSubPage || _isInDeviceSettings != inSettings)) {
          setState(() {
            _isInMonitorSubPage = inSubPage;
            _isInDeviceSettings = inSettings;
            // 當退回設備列表首頁 (不再處於子頁面) 時，自動清空選取的機台狀態
            if (!inSubPage) {
              GlobalDeviceState.clear();
            }
          });
        }
      },
    );
    _profileNavObserver = _SubNavObserver(
      onStateChanged: (inSubPage, _) {
        if (mounted && _isInProfileSubPage != inSubPage) {
          setState(() => _isInProfileSubPage = inSubPage);
        }
      },
    );
    _syncUserProfileFromServer();
  }

  Future<void> _syncUserProfileFromServer() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Future.delayed(const Duration(milliseconds: 300));

      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      if (mounted) {
        setState(() {
          _globalNickname = data['nickname'] ?? '未命名用戶';
          _globalRole = data['role'] ?? '一般使用者';
          _globalEmail = user.email ?? '';

          if (data['push_notifications_enabled'] != null) {
            GlobalState.isPushNotificationEnabled = data['push_notifications_enabled'] as bool;
          }
          if (data['backup_protection_enabled'] != null) {
            GlobalState.isBackupProtectionEnabled = data['backup_protection_enabled'] as bool;
          }

          final String? rawUrl = data['avatar_url'];
          if (rawUrl != null) {
            _globalAvatarUrl = "$rawUrl?cache=${DateTime.now().microsecondsSinceEpoch}";
          } else {
            _globalAvatarUrl = null;
          }
          _isGlobalProfileLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGlobalProfileLoading = false;
          _globalNickname = '儲能工程師';
        });
      }
    }
  }

  // 🎯 點擊左側「設定」子項目時：在右側局部 Navigator 開啟當前逆變器專屬的「系統設定」頁面
  void _onTapSidebarDeviceSettings() {
    final String? targetDeviceId = GlobalDeviceState.deviceId;
    final String targetSn = GlobalDeviceState.sn;
    if (targetDeviceId == null || targetDeviceId.isEmpty) return;

    // 若原本在「我的」分頁，先切回第 0 頁 (監控區)
    if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
      });
    }

    // 若目前已經在「設定」或其子頁面 (如電價方案/排程設定)，點擊左側「設定」會退回「系統設定」主選單，避免重複堆疊
    if (_isInDeviceSettings) {
      _monitorNavigatorKey.currentState?.popUntil(
        (route) => route.settings.name == 'device_settings' || route.isFirst,
      );
      return;
    }

    // 推入當前逆變器專屬的 SettingsSubMenuScreen 至右側區域
    _monitorNavigatorKey.currentState?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'device_settings'),
        builder: (context) => SettingsSubMenuScreen(
          deviceDbId: targetDeviceId,
          accountType: _globalRole,
          inverterSn: targetSn,
        ),
      ),
    );
  }

  // 🎯 手機寬版專用：高通透感無邊線毛玻璃左側導覽列
  Widget _buildMobileWideSidebar() {
    // 是否顯示「設定」子按鈕：當進入某台逆變器的「總覽」或相關子頁面時顯示，退出時自動隱藏！
    final bool showDeviceSettingsButton =
        _isInMonitorSubPage && (GlobalDeviceState.deviceId != null);

    return SizedBox(
      width: _sidebarWidth,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF146B60).withValues(alpha: 0.28),
                  const Color(0xFF0D4740).withValues(alpha: 0.22),
                ],
              ),
            ),
            child: SafeArea(
              left: false,
              right: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 28),
                  const Center(
                    child: Text(
                      'FTESS Home',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  // 1. 「設備列表」主按鈕 (點擊直接回到設備列表頁面，同時自動收起下方的「設定」)
                  _buildSidebarItem(
                    icon: Icons.grid_view_rounded,
                    label: '設備列表',
                    isSelected: _currentIndex == 0 && !_isInDeviceSettings,
                    onTap: () {
                      if (_currentIndex != 0) {
                        setState(() {
                          _currentIndex = 0;
                        });
                      } else {
                        // 退回設備列表首頁，_monitorNavObserver 會自動將 _isInMonitorSubPage 設為 false 並隱藏「設定」按鈕
                        _monitorNavigatorKey.currentState?.popUntil((route) => route.isFirst);
                        GlobalDeviceState.clear();
                      }
                    },
                  ),

                  // 🎯 2. 動態展開的「設定」子按鈕 (僅在進入逆變器時顯示於「設備列表」下方，字體較小，並自動將「我的」往下推)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: showDeviceSettingsButton
                        ? Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _buildSidebarSubItem(
                              icon: Icons.settings_suggest_rounded,
                              label: '設定',
                              isSelected: _currentIndex == 0 && _isInDeviceSettings,
                              onTap: _onTapSidebarDeviceSettings,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 8),

                  // 3. 「我的」主按鈕 (會隨著上方「設定」出現/消失自動往下或往上排列)
                  _buildSidebarItem(
                    icon: Icons.person_pin_rounded,
                    label: '我的',
                    isSelected: _currentIndex == 1,
                    onTap: () {
                      if (_currentIndex != 1) {
                        setState(() {
                          _currentIndex = 1;
                        });
                        _syncUserProfileFromServer();
                      } else {
                        _profileNavigatorKey.currentState?.popUntil((route) => route.isFirst);
                      }
                    },
                  ),

                  const Spacer(),

                  Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_currentIndex != 1) {
                        setState(() => _currentIndex = 1);
                        _syncUserProfileFromServer();
                      } else {
                        _profileNavigatorKey.currentState?.popUntil((route) => route.isFirst);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.teal.shade700.withValues(alpha: 0.7),
                            backgroundImage: _globalAvatarUrl != null
                                ? NetworkImage(_globalAvatarUrl!)
                                : null,
                            child: _globalAvatarUrl == null
                                ? const Icon(Icons.person, color: Colors.white, size: 22)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _globalEmail.isNotEmpty ? _globalEmail : _globalNickname,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _globalRole,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 主選單項目 (設備列表、我的 - 字體 16px)
  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Material(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected
                ? BorderSide(color: Colors.white.withValues(alpha: 0.30), width: 1)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Icon(
                    icon,
                    color: isSelected ? Colors.tealAccent : Colors.white70,
                    size: 22,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🎯 子選單項目 (專供「設備列表」下方的「設定」使用：適度縮排 + 較小字體 14px + 較小圖示 18px)
  Widget _buildSidebarSubItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 28, right: 12), // 左側微幅縮排，呈現清晰的從屬層級感
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Material(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: isSelected
                ? BorderSide(color: Colors.white.withValues(alpha: 0.30), width: 1)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Icon(
                    icon,
                    color: isSelected ? Colors.tealAccent : Colors.white70,
                    size: 18, // 較小圖示
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 14, // 較小字體 (主選單為 16)
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSharedBodyContent() {
    return IndexedStack(
      index: _currentIndex,
      children: [
        Navigator(
          key: _monitorNavigatorKey,
          observers: [_monitorNavObserver],
          onGenerateRoute: (settings) {
            return MaterialPageRoute(
              builder: (context) => DeviceListScreen(
                onSelectedInverterChanged: (deviceDbId, isOnline, customName, sn) {
                  // 當點選逆變器卡片時，觸發重建以確保左側選單即時讀取最新機台資訊
                  if (mounted) setState(() {});
                },
                accountType: _globalRole,
              ),
            );
          },
        ),
        Navigator(
          key: _profileNavigatorKey,
          observers: [_profileNavObserver],
          onGenerateRoute: (settings) {
            return MaterialPageRoute(
              builder: (context) => ProfileScreen(
                nickname: _globalNickname,
                accountType: _globalRole,
                userEmail: _globalEmail,
                avatarUrl: _globalAvatarUrl,
                onLogout: widget.onLogout,
                onProfileDataChanged: _syncUserProfileFromServer,
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobileWide = context.isMobileWideLayout;

    if (_isGlobalProfileLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.tealAccent),
          ),
        ),
      );
    }

    final bool shouldHideBottomNav = isMobileWide ||
        (_currentIndex == 0 && _isInMonitorSubPage) ||
        (_currentIndex == 1 && _isInProfileSubPage);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentIndex == 0 && (_monitorNavigatorKey.currentState?.canPop() ?? false)) {
          _monitorNavigatorKey.currentState?.pop();
        } else if (_currentIndex == 1 && (_profileNavigatorKey.currentState?.canPop() ?? false)) {
          _profileNavigatorKey.currentState?.pop();
        } else if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: MediaQuery.removePadding(
          context: context,
          removeLeft: isMobileWide,
          child: Stack(
            children: [
              if (isMobileWide)
                const Positioned.fill(
                  child: RepaintBoundary(
                    child: RealisticWeatherBg(
                      condition: WeatherCondition.sunny,
                      child: SizedBox.shrink(),
                    ),
                  ),
                ),

              Positioned.fill(
                left: isMobileWide ? _sidebarWidth : 0.0,
                child: _buildSharedBodyContent(),
              ),

              if (isMobileWide)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  child: _buildMobileWideSidebar(),
                ),
            ],
          ),
        ),
        bottomNavigationBar: shouldHideBottomNav
            ? null
            : BottomNavigationBar(
                backgroundColor: Colors.white,
                selectedItemColor: Colors.teal,
                unselectedItemColor: Colors.black38,
                currentIndex: _currentIndex,
                onTap: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                  if (index == 1) {
                    _syncUserProfileFromServer();
                  }
                },
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: '監控'),
                  BottomNavigationBarItem(icon: Icon(Icons.person_pin_rounded), label: '我的'),
                ],
              ),
      ),
    );
  }
}