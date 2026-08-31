import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import 'device_list_screen.dart';
import 'profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  const MainNavigationScreen({super.key, required this.onLogout});

  @override State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  String _globalNickname = '載入中...';
  String _globalRole = '一般使用者';
  String _globalEmail = '';
  String? _globalAvatarUrl;
  bool _isGlobalProfileLoading = true;

  @override
  void initState() {
    super.initState();
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
        setState(() { _isGlobalProfileLoading = false; _globalNickname = '儲能工程師'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isGlobalProfileLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.tealAccent)))
          : IndexedStack(
              index: _currentIndex,
              children: [
                DeviceListScreen(
                  onSelectedInverterChanged: (newName, status, dbId) {},
                  accountType: _globalRole,
                ),
                ProfileScreen(
                  nickname: _globalNickname,
                  accountType: _globalRole,
                  userEmail: _globalEmail,
                  avatarUrl: _globalAvatarUrl,
                  onLogout: widget.onLogout,
                  onProfileDataChanged: _syncUserProfileFromServer,
                ),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.black38,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() { _currentIndex = index; });
          if (index == 1) {
            _syncUserProfileFromServer();
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: '監控'),
          BottomNavigationBarItem(icon: Icon(Icons.person_pin_rounded), label: '我的'),
        ],
      ),
    );
  }
}