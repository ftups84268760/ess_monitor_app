import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'settings_screens.dart';

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

      widget.onProfileDataChanged();
      setState(() { _isActionLoading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('頭像上傳成功！'), backgroundColor: Colors.teal));
      }
    } catch (e) {
      setState(() { _isActionLoading = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('頭像上傳異常')));
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
      builder: (context) => AlertDialog(
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              final newName = _nicknameEditController.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(context);

              setState(() { _isActionLoading = true; });
              try {
                final uid = Supabase.instance.client.auth.currentUser?.id;
                await Supabase.instance.client.from('profiles').update({'nickname': newName}).eq('id', uid!);
                widget.onProfileDataChanged();
                setState(() { _isActionLoading = false; });
              } catch (e) {
                setState(() { _isActionLoading = false; });
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('修改密碼', style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              style: const TextStyle(color: Colors.black87, fontSize: 13),
              decoration: const InputDecoration(labelText: '請輸入全新密碼', labelStyle: TextStyle(color: Colors.black26, fontSize: 11)),
            ),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              style: const TextStyle(color: Colors.black87, fontSize: 13),
              decoration: const InputDecoration(labelText: '請再次確認新密碼', labelStyle: TextStyle(color: Colors.black26, fontSize: 11)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              final p1 = _newPasswordController.text;
              final p2 = _confirmPasswordController.text;
              if (p1.isEmpty || p2.isEmpty) return;
              if (p1 != p2) return;
    
              try {
              // 1. 執行非同步操作
              await Supabase.instance.client.auth.updateUser(UserAttributes(password: p1));
      
              // 2. 檢查 context 本身是否還有效 (解決 use_build_context_synchronously)
              if (!context.mounted) return; 
      
              // 3. 安全地使用 context
              Navigator.pop(context);
      
              } catch (e) {
              // 解決 empty_catches 警告：即使不顯示給使用者看，也建議在開發階段印出錯誤，避免 Debug 困難
             debugPrint('密碼更新失敗: $e'); 
             }
            },
            child: const Text('確認修改', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );
  }

  // 🎯 核心實作：安全的登出機制 (清空 FCM Token)
  Future<void> _handleSecureLogout() async {
    setState(() { _isActionLoading = true; }); // 啟動畫面轉圈圈，防止重複點擊
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // 先去資料庫把當前帳號的 FCM Token 註銷 (設為 null)
        await Supabase.instance.client
            .from('profiles')
            .update({'fcm_token': null})
            .eq('id', user.id);
      }
    } catch (e) {
      debugPrint('清除 FCM Token 失敗: $e');
      // 即使清除 Token 失敗（例如沒網路），我們還是要讓使用者登出，所以這裡只做 debugPrint
    } finally {
      // 確保將狀態回傳並執行原本的登出邏輯 (通常會包含 Supabase 登出與畫面跳轉)
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
                          CircleAvatar(
                            radius: 46,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: widget.avatarUrl != null ? NetworkImage(widget.avatarUrl!) : null,
                            child: widget.avatarUrl == null
                                ? const Text('FT', style: TextStyle(fontSize: 28, color: Colors.teal, fontWeight: FontWeight.bold))
                                : null,
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
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                        child: Text(widget.accountType, style: const TextStyle(color: Colors.teal, fontSize: 11)),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                const Text('個人化設定', style: TextStyle(color: Colors.black38, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Card(
                  color: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[100]!)),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.manage_accounts, color: Colors.black45),
                        title: const Text('帳號類型', style: TextStyle(color: Colors.black87, fontSize: 13)),
                        trailing: Text(widget.accountType, style: const TextStyle(color: Colors.black45, fontSize: 12)),
                      ),
                      const Divider(color: Colors.black12, height: 1),
                      ListTile(
                        leading: const Icon(Icons.lock_reset_rounded, color: Colors.black45),
                        title: const Text('修改密碼', style: TextStyle(color: Colors.black87, fontSize: 13)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.black26),
                        onTap: _changePasswordDialog,
                      ),
                      const Divider(color: Colors.black12, height: 1),
                     ListTile(
                        leading: const Icon(Icons.notifications_active_outlined, color: Colors.black45),
                        title: const Text('系統推播通知設定', style: TextStyle(color: Colors.black87, fontSize: 13)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.black26),
                        onTap: () async {
                          final user = Supabase.instance.client.auth.currentUser;
                          if (user != null) {
                            try {
                              // 🎯 替換：呼叫 RPC，讓「自己擁有」和「別人分享」的設備都能通過檢查
                              final response = await Supabase.instance.client.rpc('get_accessible_devices');
                              final List devices = response as List;

                              if (!context.mounted) return;

                              // 🎯 判斷設備清單是否為空
                              if (devices.isNotEmpty) {
                                // 有設備：取第一台設備的 ID 正常跳轉
                                Navigator.push(
                                  context, 
                                  MaterialPageRoute(
                                    builder: (context) => PushNotificationSettingsScreen(deviceDbId: devices.first['id'].toString())
                                  )
                                );
                              } else {
                                // 無設備：彈出友善的提示訊息
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('系統連線異常，請稍後再試。'), backgroundColor: Colors.redAccent)
                                );
                              }
                            }
                          }
                        },
                      ),
                      const Divider(color: Colors.black12, height: 1),
                      ListTile(
                        leading: const Icon(Icons.info_outline_rounded, color: Colors.black45),
                        title: const Text('軟體資訊', style: TextStyle(color: Colors.black87, fontSize: 13)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.black26),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SoftwareInfoScreen()),
                          );
                        },
                      ),
                      const Divider(color: Colors.black12, height: 1),
                      ListTile(
                        leading: const Icon(Icons.no_accounts_rounded, color: Colors.redAccent),
                        title: const Text('帳號刪除註銷', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.black26, size: 18),
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
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.red[50],
                    foregroundColor: Colors.red[700],
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.red[200]!, width: 0.5)),
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Colors.white,
                        title: const Text('登出', style: TextStyle(color: Colors.black87, fontSize: 16)),
                        content: const Text('您確定要登出嗎？', style: TextStyle(color: Colors.black54, fontSize: 12)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                          TextButton(
                            // 🎯 替換：改呼叫我們寫好的 _handleSecureLogout
                            onPressed: () { Navigator.pop(context); _handleSecureLogout(); },
                            child: const Text('確定登出', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('帳號登出', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
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
      setState(() {
        _deviceCount = (response as List).length;
        _canDelete = _deviceCount == 0;
        _isCheckingConditions = false;
      });
    } catch (e) {
      setState(() { _isCheckingConditions = false; });
    }
  }

  Future<void> _executeAccountDeletion() async {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('註銷確認', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text('您確定要完全註銷此帳號嗎？此操作將會清除所有雲端數據，且永遠無法被恢復。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              navigator.pop();
              try {
                final user = Supabase.instance.client.auth.currentUser;
                if (user != null) {
                  await Supabase.instance.client.storage.from('avatars').remove(['${user.id}.jpg']);
                }

                await Supabase.instance.client.rpc('delete_user_own_account');
                await widget.onLogout();
                navigator.pop();

                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('您的帳號已成功銷毀註銷，感謝您的使用。'), backgroundColor: Colors.teal)
                );
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('註銷執行失敗，請確認雲端連線狀態。'), backgroundColor: Colors.redAccent)
                );
              }
            },
            child: const Text('確定註銷', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
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
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
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
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        elevation: 0,
                      ),
                      onPressed: _canDelete ? _executeAccountDeletion : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('您的帳號目前仍綁定設備，請先退回設備清單刪除所有設備後再進行註銷。'))
                        );
                      },
                      child: const Text('確認註銷', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SoftwareInfoScreen extends StatelessWidget {
  const SoftwareInfoScreen({super.key});

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
      backgroundColor: const Color(0xFFF5F5F5),
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
            padding: const EdgeInsets.symmetric(vertical: 30),
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
                        blurRadius: 8,
                        offset: const Offset(0, 2),
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
                const Text('Version 1.0.0', style: TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          Expanded(
            child: Container(
              color: Colors.white,
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 20, top: 16, bottom: 8),
                    child: Text('隱私權政策', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                  const Divider(height: 1, color: Colors.black12),
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
        ],
      ),
    );
  }
}