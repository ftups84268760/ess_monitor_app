import 'dart:io';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'settings_screens.dart';
import 'package:package_info_plus/package_info_plus.dart';

// 🎯 引入 Logger
import '../utils/audit_logger.dart';

// 🎯 全域共用的網路異常訊息轉換器
String _getFriendlyErrorMsg(dynamic e) {
  final String errorMsg = e.toString();
  if (errorMsg.contains('SocketException') || errorMsg.contains('Failed host lookup')) {
    return '無法連線至雲端伺服器，請檢查您的 Wi-Fi 或網路連線狀態。';
  }
  return '錯誤細節: $errorMsg';
}

class ProfileScreen extends StatefulWidget {
  final String nickname;
  final String accountType;
  final String userEmail;
  final String? avatarUrl;
  final Future<void> Function() onLogout;
  final VoidCallback onProfileDataChanged;

  const ProfileScreen({
    super.key,
    required this.nickname,
    required this.accountType,
    required this.userEmail,
    required this.avatarUrl,
    required this.onLogout,
    required this.onProfileDataChanged,
  });
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isActionLoading = false;
  final TextEditingController _nicknameEditController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source, imageQuality: 70);
    if (image == null) return;

    setState(() { _isActionLoading = true; });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final File file = File(image.path);
      final String fileName = '${user.id}.jpg';
      await Supabase.instance.client.storage.from('avatars').upload(
        fileName,
        file,
        fileOptions: const FileOptions(cacheControl: '0', upsert: true),
      );
      final String publicUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl(fileName);
      await Supabase.instance.client.from('profiles').update({'avatar_url': publicUrl}).eq('id', user.id);

      // 🎯 紀錄: 變更頭像
      await logUserAction('更改個人資料', details: '上傳並更新了個人頭像圖片');

      widget.onProfileDataChanged();
      
      if (!mounted) return;
      setState(() { _isActionLoading = false; });
      ScaffoldMessenger.of(context).clearSnackBars(); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('頭像上傳成功！'), backgroundColor: Colors.teal));
    } catch (e) {
      if (!mounted) return;
      setState(() { _isActionLoading = false; });
      ScaffoldMessenger.of(context).clearSnackBars(); 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('頭像上傳異常: ${_getFriendlyErrorMsg(e)}'), backgroundColor: Colors.redAccent));
    }
  }

  void _showAvatarSourceBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.teal),
              title: const Text('從手機相簿選取', style: TextStyle(color: Colors.black87)),
              onTap: () { Navigator.pop(context); _pickAndUploadAvatar(ImageSource.gallery); },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.teal),
              title: const Text('開啟相機拍照', style: TextStyle(color: Colors.black87)),
              onTap: () { Navigator.pop(context); _pickAndUploadAvatar(ImageSource.camera); },
            ),
          ],
        ),
      ),
    );
  }

  void _editNicknameDialog() {
    _nicknameEditController.text = widget.nickname;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('修改個人暱稱', style: TextStyle(color: Colors.black87, fontSize: 15)),
        content: TextField(
          controller: _nicknameEditController,
          style: const TextStyle(color: Colors.black87),
          decoration: const InputDecoration(
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.teal)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              final newName = _nicknameEditController.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(dialogContext);

              setState(() { _isActionLoading = true; });
              try {
                final uid = Supabase.instance.client.auth.currentUser?.id;
                await Supabase.instance.client.from('profiles').update({'nickname': newName}).eq('id', uid!);
                
                // 🎯 紀錄: 變更暱稱
                await logUserAction('更改個人資料', details: '將個人暱稱更改為: $newName');
                
                widget.onProfileDataChanged();
                
                if (!mounted) return;
                setState(() { _isActionLoading = false; });
              } catch (e) {
                if (!mounted) return;
                setState(() { _isActionLoading = false; });
                ScaffoldMessenger.of(context).clearSnackBars(); 
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('修改失敗: ${_getFriendlyErrorMsg(e)}'), backgroundColor: Colors.redAccent));
              }
            },
            child: const Text('儲存', style: TextStyle(color: Colors.teal))
          ),
        ],
      ),
    );
  }

  void _changePasswordDialog() {
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    
    bool isNewPasswordVisible = false;
    bool isConfirmPasswordVisible = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (contextBuilder, setStateDialog) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              backgroundColor: Colors.black.withValues(alpha: 0.6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
              ),
              title: const Text('修改密碼', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _newPasswordController,
                    obscureText: !isNewPasswordVisible,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '新密碼(最少6個字元)',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isNewPasswordVisible ? Icons.visibility : Icons.visibility_off,
                          color: Colors.white54,
                          size: 20,
                        ),
                        onPressed: () {
                          setStateDialog(() {
                            isNewPasswordVisible = !isNewPasswordVisible;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: !isConfirmPasswordVisible,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '再次確認新密碼',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                          color: Colors.white54,
                          size: 20,
                        ),
                        onPressed: () {
                          setStateDialog(() {
                            isConfirmPasswordVisible = !isConfirmPasswordVisible;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消', style: TextStyle(color: Colors.grey))
                ),
                TextButton(
                  onPressed: () async {
                    final p1 = _newPasswordController.text;
                    final p2 = _confirmPasswordController.text;
                    
                    if (p1.isEmpty || p2.isEmpty) return;
                    if (p1 != p2) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('兩次密碼不一致')));
                      return;
                    }
                    if (p1.length < 6) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密碼長度至少需要6個字元')));
                      return;
                    }

                    try {
                      await Supabase.instance.client.auth.updateUser(UserAttributes(password: p1));
                      
                      // 🎯 紀錄: 變更密碼
                      await logUserAction('更改帳號安全設定', details: '使用者成功變更了登入密碼');

                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密碼更新成功！', style: TextStyle(color: Colors.white)), backgroundColor: Colors.teal));
                    } catch (e) {
                      debugPrint('密碼更新失敗: $e'); 
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('密碼更新失敗: ${_getFriendlyErrorMsg(e)}', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
                    }
                  },
                  child: const Text('確認修改', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  Future<void> _handleSecureLogout() async {
    setState(() { _isActionLoading = true; }); 
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({'fcm_token': null})
            .eq('id', user.id);
      }

      // 🎯 紀錄: 登出 (依照平台給予不同的細節描述)
      String platform = kIsWeb ? '網頁版後台' : '手機 APP';
      await logUserAction('登出', details: '使用者從 $platform 登出系統');

    } catch (e) {
      debugPrint('清除 FCM Token 失敗: $e');
    } finally {
      await widget.onLogout();
      if (mounted) {
        setState(() { _isActionLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isActionLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 14),
                      Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))
                              ]
                            ),
                            child: CircleAvatar(
                              radius: 46,
                              backgroundColor: Colors.grey[100],
                              backgroundImage: widget.avatarUrl != null ? NetworkImage(widget.avatarUrl!) : null,
                              child: widget.avatarUrl == null
                                  ? const Text('FT', style: TextStyle(fontSize: 28, color: Colors.teal, fontWeight: FontWeight.bold))
                                  : null,
                            ),
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: CircleAvatar(
                              radius: 16, backgroundColor: Colors.teal,
                              child: IconButton(
                                icon: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                                onPressed: _showAvatarSourceBottomSheet,
                              ),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.nickname,
                            style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.black26, size: 16),
                            onPressed: _editNicknameDialog,
                          )
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.userEmail.isNotEmpty ? widget.userEmail : "未取得帳號資訊",
                        style: const TextStyle(color: Colors.black38, fontSize: 13, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                        child: Text(widget.accountType, style: const TextStyle(color: Colors.teal, fontSize: 11, fontWeight: FontWeight.w600)),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text('個人化設定', style: TextStyle(color: Colors.black45, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))
                    ]
                  ),
                  child: Column(
                    children: [
                      if (widget.accountType == '系統管理員(root)') ...[
                        ListTile(
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                          leading: const Icon(Icons.admin_panel_settings, color: Colors.redAccent),
                          title: const Text('進階設定(root權限)', style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.black26),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const SystemAdvancedSettingsScreen()),
                            );
                          },
                        ),
                        const Divider(color: Color(0xFFF1F5F9), height: 1),
                      ],
                      ListTile(
                        leading: const Icon(Icons.lock_reset_rounded, color: Colors.teal),
                        title: const Text('修改密碼', style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.black26),
                        onTap: _changePasswordDialog,
                      ),
                      const Divider(color: Color(0xFFF1F5F9), height: 1),
                      ListTile(
                        leading: const Icon(Icons.notifications_active_rounded, color: Colors.teal),
                        title: const Text('系統推播通知設定', style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.black26),
                        onTap: () async {
                          final user = Supabase.instance.client.auth.currentUser;
                          if (user != null) {
                            try {
                              final response = await Supabase.instance.client.rpc('get_accessible_devices');
                              final List devices = response as List;

                              if (!context.mounted) return;

                              if (devices.isNotEmpty) {
                                Navigator.push(
                                  context, 
                                  MaterialPageRoute(
                                    builder: (context) => PushNotificationSettingsScreen(deviceDbId: devices.first['id'].toString())
                                  )
                                );
                              } else {
                                ScaffoldMessenger.of(context).clearSnackBars(); 
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('請先新增首台設備(或 接收分享設備)，即可開啟推播設定。'),
                                    backgroundColor: Colors.orangeAccent,
                                  ),
                                );
                              }
                            } catch (e) {
                              debugPrint('無法取得設備ID以進入推播設定: $e');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).clearSnackBars(); 
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('系統連線異常: ${_getFriendlyErrorMsg(e)}'), backgroundColor: Colors.redAccent)
                                );
                              }
                            }
                          }
                        },
                      ),
                      const Divider(color: Color(0xFFF1F5F9), height: 1),
                      ListTile(
                        leading: const Icon(Icons.info_rounded, color: Colors.teal),
                        title: const Text('軟體資訊', style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.black26),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SoftwareInfoScreen()),
                          );
                        },
                      ),
                      const Divider(color: Color(0xFFF1F5F9), height: 1),
                      ListTile(
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
                        leading: const Icon(Icons.no_accounts_rounded, color: Colors.redAccent),
                        title: const Text('帳號刪除註銷', style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.redAccent, size: 18),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => AccountDeletionScreen(onLogout: widget.onLogout)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.red.shade600, 
                      foregroundColor: Colors.white,        
                      elevation: 2,                         
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: AlertDialog(
                            backgroundColor: Colors.black.withValues(alpha: 0.6),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3), width: 1.5),
                            ),
                            title: const Text('登出', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                            content: const Text('您確定要登出並離開系統嗎？', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                              TextButton(
                                onPressed: () { Navigator.pop(context); _handleSecureLogout(); },
                                child: const Text('確定登出', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: const Text('帳號登出', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
      ),
    );
  }
}

class AccountDeletionScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  const AccountDeletionScreen({super.key, required this.onLogout});

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  bool _isCheckingConditions = true;
  bool _canDelete = false;
  int _deviceCount = 0;

  @override
  void initState() {
    super.initState();
    _checkEligibilityConditions();
  }

  Future<void> _checkEligibilityConditions() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final response = await Supabase.instance.client
          .from('devices')
          .select('id')
          .eq('user_id', user.id);
      
      if (!mounted) return;
      setState(() {
        _deviceCount = (response as List).length;
        _canDelete = _deviceCount == 0;
        _isCheckingConditions = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars(); 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('驗證失敗: ${_getFriendlyErrorMsg(e)}'), backgroundColor: Colors.redAccent));
      setState(() { _isCheckingConditions = false; });
    }
  }

  Future<void> _executeAccountDeletion() async {
    showDialog(
      context: context,
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: Colors.black.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3), width: 1.5),
          ),
          title: const Text('註銷確認', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: const Text('您確定要完全註銷此帳號嗎？此操作將會清除所有雲端數據，且永遠無法被恢復。', style: TextStyle(color: Colors.white70, height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消', style: TextStyle(color: Colors.grey))),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext); // 先關閉對話框
                
                try {
                  final user = Supabase.instance.client.auth.currentUser;
                  if (user != null) {
                    await Supabase.instance.client.storage.from('avatars').remove(['${user.id}.jpg']);
                  }

                  // 🎯 紀錄: 註銷帳號 (註銷完成後使用者會立刻被登出)
                  await logUserAction('註銷帳號', details: '使用者已主動註銷並永久刪除該帳號');

                  await Supabase.instance.client.rpc('delete_user_own_account');
                  await widget.onLogout();

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).clearSnackBars(); 
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('您的帳號已成功銷毀註銷，感謝您的使用。'), backgroundColor: Colors.teal)
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).clearSnackBars(); 
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('註銷執行失敗: ${_getFriendlyErrorMsg(e)}'), backgroundColor: Colors.redAccent)
                  );
                }
              },
              child: const Text('確定註銷', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: AppBar(
        title: const Text('註銷帳號', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isCheckingConditions ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal))) : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))]
                    ),
                    child: const Text(
                      '1. 註銷帳號後，您的身份、帳號、設備資訊與資料都將會被清空，並且無法恢復。\n\n'
                      '2. 註銷帳號後，您可重新使用該電子信箱進行註冊，但相關資訊將被清空。\n\n'
                      '3. 註銷帳號狀態必須滿足帳號無設備，請註銷前先刪除以上內容後再繼續註銷帳號操作。',
                      style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '註銷帳號,您必須滿足以下條件::',
                          style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('-帳號下沒有任何設備：', style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('需要刪除帳號下的所有設備 (目前殘留: $_deviceCount 台)', style: const TextStyle(color: Colors.black38, fontSize: 12)),
                              ],
                            ),
                            Icon(_canDelete ? Icons.check_circle : Icons.cancel, color: _canDelete ? Colors.green : Colors.red, size: 20),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  const Text(
                    '點選下方「確認註銷」按鈕，即代表您已閱讀以上內容並同意註銷該帳號。',
                    style: TextStyle(color: Colors.black45, fontSize: 11, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canDelete ? const Color(0xFFFF522D) : Colors.grey[400],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12), 
                        ),
                        elevation: 0,
                      ),
                      onPressed: _canDelete ? _executeAccountDeletion : () {
                        ScaffoldMessenger.of(context).clearSnackBars(); 
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('您的帳號目前仍綁定設備，請先退回設備清單刪除所有設備後再進行註銷。'))
                        );
                      },
                      child: const Text('確認註銷', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SoftwareInfoScreen extends StatefulWidget {
  const SoftwareInfoScreen({super.key});

  @override
  State<SoftwareInfoScreen> createState() => _SoftwareInfoScreenState();
}

class _SoftwareInfoScreenState extends State<SoftwareInfoScreen> {
  String _version = '讀取中...'; 

  @override
  void initState() {
    super.initState();
    _initPackageInfo(); 
  }

  Future<void> _initPackageInfo() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      setState(() {
        _version = '${info.version} (Build ${info.buildNumber})'; 
      });
    } catch (e) {
      setState(() {
        _version = '版本讀取失敗';
      });
    }
  }

  Future<String> _loadPrivacyPolicy() async {
    try {
      return await rootBundle.loadString('assets/privacy_policy.txt');
    } catch (e) {
      return '無法載入隱私政策，請確認檔案路徑是否正確。';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: AppBar(
        title: const Text('軟體資訊', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ], 
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16), 
                    child: Image.asset(
                      'assets/icon.png', 
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('FTESS Home', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 6),
                Text('Version $_version', style: const TextStyle(fontSize: 13, color: Colors.teal, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))]
              ),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 20, top: 16, bottom: 8),
                    child: Text('隱私權政策', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  Expanded(
                    child: FutureBuilder<String>(
                      future: _loadPrivacyPolicy(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Colors.teal));
                        } else if (snapshot.hasError) {
                          return const Center(child: Text('讀取失敗', style: TextStyle(color: Colors.red)));
                        } else {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              snapshot.data ?? '',
                              style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.6),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}