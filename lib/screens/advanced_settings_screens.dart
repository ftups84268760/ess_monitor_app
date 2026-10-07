import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
// 🎯 引入 Logger
import '../utils/audit_logger.dart';
// 🎯 引入 DTU 更換畫面
import 'dashboard/dtu_replacement_screen.dart';

String _getFriendlyErrorMsg(dynamic e) {
  final String errorMsg = e.toString();
  if (errorMsg.contains('SocketException') || errorMsg.contains('Failed host lookup')) {
    return '無法連線至雲端伺服器，請檢查您的 Wi-Fi 或網路連線狀態。';
  }
  return '錯誤細節: $errorMsg';
}

// ==========================================
// 管理員權限設定
// ==========================================
class AdminPromotionScreen extends StatefulWidget {
  const AdminPromotionScreen({super.key});

  @override
  State<AdminPromotionScreen> createState() => _AdminPromotionScreenState();
}

class _AdminPromotionScreenState extends State<AdminPromotionScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isProcessing = false;

  Future<void> _changeAdminRole(bool makeAdmin) async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars(); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請輸入欲設定的帳號信箱')));
      return;
    }

    if (!makeAdmin) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('撤銷權限確認', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('確定要將 $email 降級為一般使用者嗎？\n對方將立即失去全系統設備的檢視與操作權限。', style: const TextStyle(height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消', style: TextStyle(color: Colors.grey))),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('確定撤銷', style: TextStyle(color: Colors.red))),
          ],
        )
      );
      if (confirm != true) return;
    }

    setState(() => _isProcessing = true);

    try {
      final rpcName = makeAdmin ? 'promote_to_admin_by_email' : 'demote_from_admin_by_email';
      final response = await Supabase.instance.client.rpc(
        rpcName,
        params: {'target_email': email},
      );

      if (!mounted) return;

      if (response['success'] == true) {
        _emailController.clear();
        FocusScope.of(context).unfocus(); 
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.teal));
      } else {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMsg(e)), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('管理員權限', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16)),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.admin_panel_settings_rounded, color: Colors.redAccent, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('升級權限，該帳號將獲得系統管理員權限。若撤銷權限，該帳號將恢復一般使用者權限', style: TextStyle(fontSize: 13, color: Colors.redAccent, height: 1.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text('輸入欲設定的帳號(電子郵件)：', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'example@email.com',
                prefixIcon: const Icon(Icons.email_outlined, color: Colors.teal),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
              ),
            ),
            const SizedBox(height: 24),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal, 
                      padding: const EdgeInsets.symmetric(vertical: 14), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    onPressed: _isProcessing ? null : () => _changeAdminRole(true),
                    child: _isProcessing 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('升級權限', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14), 
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: _isProcessing ? Colors.grey : Colors.redAccent)
                      )
                    ),
                    onPressed: _isProcessing ? null : () => _changeAdminRole(false),
                    child: const Text('撤銷權限', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 設備進階設定選單
// ==========================================
class DeviceAdvancedSettingsScreen extends StatelessWidget {
  final String deviceDbId;
  final String inverterSn;
  final bool isRootOrOwner; 
  final bool isRoot; 

  const DeviceAdvancedSettingsScreen({
    super.key, 
    required this.deviceDbId, 
    required this.inverterSn, 
    required this.isRootOrOwner,
    this.isRoot = false,
  });

  void _promptDtuPassword(BuildContext parentContext) {
    final TextEditingController pwdController = TextEditingController();
    bool isPasswordVisible = false; 

    showDialog(
      context: parentContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setState) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              backgroundColor: Colors.black.withValues(alpha: 0.6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
              ),
              title: const Text('需要密碼授權', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              content: TextField(
                controller: pwdController,
                obscureText: !isPasswordVisible, 
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '請輸入通訊模組更換密碼',
                  hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                  enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      isPasswordVisible ? Icons.visibility : Icons.visibility_off, 
                      color: Colors.white54
                    ),
                    onPressed: () {
                      setState(() {
                        isPasswordVisible = !isPasswordVisible; 
                      });
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                TextButton(
                  onPressed: () {
                    if (pwdController.text == 'ftups84268760') {
                      Navigator.pop(dialogContext); 
                      Navigator.push(parentContext, MaterialPageRoute(
                        builder: (context) => DtuReplacementScreen(deviceDbId: deviceDbId, inverterSn: inverterSn)
                      ));
                    } else {
                      Navigator.pop(dialogContext); 
                      ScaffoldMessenger.of(parentContext).clearSnackBars(); 
                      ScaffoldMessenger.of(parentContext).showSnackBar(const SnackBar(content: Text('授權密碼錯誤，拒絕存取！'), backgroundColor: Colors.redAccent));
                    }
                  },
                  child: const Text('確認執行', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                )
              ]
            ),
          );
        }
      )
    );
  }

  void _promptTransferDevice(BuildContext parentContext) {
    final TextEditingController emailController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: parentContext,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.3), 
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setState) { 
          return AlertDialog(
            backgroundColor: Colors.black87, 
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
            ),
            title: const Row(
              children: [
                Icon(Icons.send_to_mobile_rounded, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text('設備移轉', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('請輸入接收者的註冊帳號(電子郵件)，系統將產生一組6位數接收碼。', style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.5)),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: '接收者帳號(電子郵件)',
                    labelStyle: TextStyle(color: Colors.white54, fontSize: 13),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent)),
                    prefixIcon: Icon(Icons.email_outlined, color: Colors.orangeAccent),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: isProcessing 
                  ? null 
                  : () async {
                      final targetEmail = emailController.text.trim();
                      if (targetEmail.isEmpty) return;
                      
                      final messenger = ScaffoldMessenger.of(parentContext);
                      final nav = Navigator.of(dialogContext);

                      setState(() => isProcessing = true);

                      try {
                        final response = await Supabase.instance.client.rpc(
                          'initiate_device_transfer',
                          params: {
                            'p_device_id': int.tryParse(deviceDbId) ?? 0, 
                            'p_target_email': targetEmail
                          },
                        );

                        nav.pop(); 

                        if (response['success'] == true) {
                          if (parentContext.mounted) {
                            _showVerificationCodeDialog(parentContext, targetEmail, response['code']);
                          }
                        } else {
                          messenger.clearSnackBars(); 
                          messenger.showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.redAccent));
                        }
                      } catch (e) {
                        nav.pop();
                        messenger.clearSnackBars(); 
                        messenger.showSnackBar(SnackBar(content: Text(_getFriendlyErrorMsg(e)), backgroundColor: Colors.redAccent));
                      }
                    },
                child: isProcessing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('產生接收碼', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
              )
            ],
          );
        }
      )
    );
  }

  void _showVerificationCodeDialog(BuildContext parentContext, String targetEmail, String code) {
    showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: Colors.black.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
          ),
          title: const Text('移轉請求已建立', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('請將以下代碼提供給 $targetEmail', style: const TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orangeAccent)),
                child: Text(code, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 8, color: Colors.orangeAccent)),
              ),
              const SizedBox(height: 20),
              const Text('對方必須在24小時內輸入此代碼，設備才會正式移轉。在對方接收前，您仍保有設備控制權。', style: TextStyle(color: Colors.redAccent, fontSize: 11, height: 1.5)),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => Navigator.of(context).pop(), 
              child: const Text('我知道了', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            )
          ]
        ),
      )
    );
  }

  void _promptForceTransfer(BuildContext parentContext) {
    final TextEditingController emailController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: parentContext,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.3), 
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setState) { 
          return AlertDialog(
            backgroundColor: Colors.black87, 
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5), width: 1.5),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_rounded, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('設備所有權強制移轉(root權限)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.redAccent)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('警告：此操作將無條件立即轉移設備所有權，並清除所有分享紀錄。', style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.5)),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: '接收者帳號(電子郵件)', 
                    labelStyle: TextStyle(color: Colors.white54, fontSize: 13),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.redAccent))
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: isProcessing ? null : () => Navigator.pop(dialogContext), child: const Text('取消', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: isProcessing 
                  ? null 
                  : () async {
                      final targetEmail = emailController.text.trim();
                      if (targetEmail.isEmpty) return;

                      final messenger = ScaffoldMessenger.of(parentContext);
                      final dialogNav = Navigator.of(dialogContext);
                      final parentNav = Navigator.of(parentContext);

                      setState(() => isProcessing = true);

                      try {
                        final response = await Supabase.instance.client.rpc(
                          'force_transfer_device_ownership',
                          params: {
                            'p_device_id': int.tryParse(deviceDbId) ?? 0, 
                            'p_target_email': targetEmail
                          },
                        );
                        
                        dialogNav.pop(); 

                        if (response['success'] == true) {
                          messenger.clearSnackBars(); 
                          messenger.showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.teal));
                          parentNav.popUntil((route) => route.isFirst); 
                        } else {
                          messenger.clearSnackBars(); 
                          messenger.showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.redAccent));
                        }
                      } catch (e) {
                        dialogNav.pop();
                        messenger.clearSnackBars(); 
                        messenger.showSnackBar(SnackBar(content: Text(_getFriendlyErrorMsg(e)), backgroundColor: Colors.redAccent));
                      }
                    },
                child: isProcessing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('強制移轉', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          );
        }
      )
    );
  }

  Widget _buildGlassTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required Color titleColor,
    required VoidCallback onTap,
    Color? bgColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: bgColor ?? Colors.white.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Icon(icon, color: iconColor),
                title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: titleColor)),
                trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: titleColor == Colors.red ? Colors.redAccent : Colors.black26),
                onTap: onTap,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      extendBody: true, 
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('進階設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset('assets/menu_full_bg.png', fit: BoxFit.cover),
            ),
            SafeArea(
              bottom: false,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                children: [
                  _buildGlassTile(
                    context: context,
                    icon: Icons.battery_charging_full_rounded,
                    iconColor: Colors.teal,
                    title: '電池參數',
                    titleColor: Colors.black87,
                    onTap: () {
                      if (!isRootOrOwner) {
                        ScaffoldMessenger.of(context).clearSnackBars(); 
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('權限不足，無法執行此功能'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 2),
                        ));
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute(
                        builder: (context) => BatteryParameterSettingsScreen(deviceDbId: deviceDbId, inverterSn: inverterSn)
                      ));
                    },
                  ),
                  _buildGlassTile(
                    context: context,
                    icon: Icons.swap_horiz_rounded,
                    iconColor: Colors.redAccent,
                    title: '通訊模組(DTU)更換',
                    titleColor: Colors.black87,
                    onTap: () => _promptDtuPassword(context),
                  ),
                  _buildGlassTile(
                    context: context,
                    icon: Icons.send_to_mobile_rounded,
                    iconColor: Colors.orange,
                    title: '設備所有權移轉',
                    titleColor: Colors.black87,
                    onTap: () {
                      if (!isRootOrOwner) {
                        ScaffoldMessenger.of(context).clearSnackBars(); 
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('權限不足，無法執行此功能'),
                          backgroundColor: Colors.orange,
                        ));
                        return;
                      }
                      _promptTransferDevice(context);
                    },
                  ),
                  if (isRoot) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: Colors.black12, height: 1),
                    ),
                    _buildGlassTile(
                      context: context,
                      icon: Icons.gavel_rounded,
                      iconColor: Colors.red,
                      title: '設備所有權強制移轉(root權限)',
                      titleColor: Colors.red,
                      bgColor: Colors.red.withValues(alpha: 0.15),
                      onTap: () => _promptForceTransfer(context),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SystemAdvancedSettingsScreen extends StatelessWidget {
  const SystemAdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('進階設定(root權限)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))]
            ),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              leading: const Icon(Icons.admin_panel_settings, color: Colors.teal),
              title: const Text('管理員權限設定', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: const Text('指派或撤銷系統管理員身分', style: TextStyle(fontSize: 12, color: Colors.black45)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black26),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPromotionScreen()));
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 電池參數設定
// ==========================================
class BatteryParameterSettingsScreen extends StatefulWidget {
  final String deviceDbId;
  final String inverterSn;
  const BatteryParameterSettingsScreen({super.key, required this.deviceDbId, required this.inverterSn});

  @override
  State<BatteryParameterSettingsScreen> createState() => _BatteryParameterSettingsScreenState();
}

class _BatteryParameterSettingsScreenState extends State<BatteryParameterSettingsScreen> with WidgetsBindingObserver {
  bool _isLoading = true; 
  MqttServerClient? _mqttClient;
  
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;

  bool _isProductB = false;

  int? _maxAcChargeCurrent;  
  int? _offGridDischargeSoc; 
  int? _offGridRecoverySoc;  
  int? _onGridDischargeSoc;  
  int? _onGridRecoverySoc; 
  
  int? _acCouplingOffSoc; 
  int? _acCouplingOnSoc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _setupDirectMqtt();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      final bool hasNetwork = !result.contains(ConnectivityResult.none);
      
      if (!hasNetwork && _isOnline) {
        _isOnline = false;
        debugPrint('⚠ 網路斷開，主動中斷 MQTT 殭屍連線');
        _mqttClient?.disconnect();
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars(); 
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('網路連線中斷，暫停讀取'), backgroundColor: Colors.orange));
        }
      } else if (hasNetwork && !_isOnline) {
        _isOnline = true;
        debugPrint('🌐 網路恢復，嘗試重新連線 MQTT');
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars(); 
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('網路已恢復，重新連線中...'), backgroundColor: Colors.teal));
          _setupDirectMqtt();
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isOnline) {
        _setupDirectMqtt();
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _mqttClient?.disconnect();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _connectivitySubscription?.cancel(); 
    _mqttClient?.disconnect(); 
    super.dispose();
  }

  Future<void> _setupDirectMqtt() async {
    final clientId = 'flutter_app_${DateTime.now().millisecondsSinceEpoch}';
    _mqttClient = MqttServerClient.withPort('vb6a817a.ala.eu-central-1.emqxsl.com', clientId, 8883);
    _mqttClient!.secure = true;
    _mqttClient!.logging(on: false);
    
    final connMessage = MqttConnectMessage()
        .authenticateAs('FTESS', '84268760') 
        .withClientIdentifier(clientId)
        .startClean();
    _mqttClient!.connectionMessage = connMessage;

    try {
      await _mqttClient!.connect();
      if (_mqttClient!.connectionStatus!.state == MqttConnectionState.connected) {
        debugPrint('✅ MQTT 直連成功，準備攔截逆變器回傳資料');
        
        _mqttClient!.subscribe('inverter/telemetry/${widget.inverterSn}', MqttQos.atMostOnce);
        
        _queryDeviceSettings();

        _mqttClient!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
          final recMess = c![0].payload as MqttPublishMessage;
          final payloadString = String.fromCharCodes(recMess.payload.message);
      
          final match = RegExp(r'\^D(092|102)').firstMatch(payloadString);
          if (match != null) {
           final header = match.group(0)!;
            final startIndex = payloadString.indexOf(header);
            final cleanString = payloadString.substring(startIndex);
            _parseBatsResponse(cleanString, header); 
          }
        });
      }
    } catch (e) {
      debugPrint('❌ MQTT 連線失敗: $e');
      _mqttClient?.disconnect();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<int> _generateList(int start, int end, int step) {
    List<int> list = [];
    for (int i = start; i <= end; i += step) {
      list.add(i);
    }
    return list;
  }

  Future<void> _queryDeviceSettings() async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-device-command',
        body: {'sn': widget.inverterSn, 'commands': ['^P005BATS\r']}, 
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMsg(e)), backgroundColor: Colors.redAccent));
      }
    } finally {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _isLoading) setState(() => _isLoading = false);
      });
    }
  }

  void _parseBatsResponse(String cleanString, String header) {
    try {
      List<String> parts = cleanString.split(',');
      int vvvv, xxx, yyy, zzz, aaa, eeeVal = 0, fffVal = 0;
      bool isDeviceB = false;

      if (header == '^D092' && parts.length >= 22) {
        isDeviceB = false;
        vvvv = int.parse(parts[16]);
        xxx = int.parse(parts[18]);
        yyy = int.parse(parts[19]);
        zzz = int.parse(parts[20]);
        aaa = int.parse(RegExp(r'^\d+').firstMatch(parts[21])?.group(0) ?? '0');
      } else if (header == '^D102' && parts.length >= 25) { 
        isDeviceB = true;
        vvvv = int.parse(parts[16]);
        xxx = int.parse(parts[18]); 
        yyy = int.parse(parts[19]);
        zzz = int.parse(parts[20]);
        aaa = int.parse(parts[21]);
        eeeVal = int.parse(parts[22]); 
        fffVal = int.parse(parts[23]);
      } else {
        return; 
      }

      setState(() {
        _isProductB = isDeviceB; 
        _maxAcChargeCurrent = (vvvv ~/ 10).clamp(10, 100);
        _offGridDischargeSoc = xxx.clamp(0, 80);
        _offGridRecoverySoc = yyy.clamp(10, 80);
        _onGridDischargeSoc = zzz.clamp(5, 95);
        _onGridRecoverySoc = aaa.clamp(10, 100);
        
        if (_isProductB) {
          _acCouplingOffSoc = eeeVal.clamp(10, 100);
          _acCouplingOnSoc = fffVal.clamp(5, 80);
        }
        _isLoading = false; 
      });
  
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已成功讀取參數'), backgroundColor: Colors.teal)
        );
      }
    } catch (e) {
      debugPrint('解析失敗: $e');
    }
  }

  Future<void> _sendAcChargeCurrent() async {
    if (_maxAcChargeCurrent == null) {
      ScaffoldMessenger.of(context).clearSnackBars(); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請稍等...'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true);
    try {
      String currentStr = (_maxAcChargeCurrent! * 10).toString().padLeft(4, '0');
      await Supabase.instance.client.functions.invoke(
        'send-device-command',
        body: {'sn': widget.inverterSn, 'commands': ['^S011MUCHGC$currentStr\r']},
      );

      await logUserAction('更改電池參數', details: '將設備 ${widget.inverterSn} 的最大充電電流設為 $_maxAcChargeCurrent A');

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('充電電流設定已發送'), backgroundColor: Colors.teal));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMsg(e)), backgroundColor: Colors.redAccent));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendSocSettings() async {
    if (_offGridDischargeSoc == null || _offGridRecoverySoc == null || _onGridDischargeSoc == null || _onGridRecoverySoc == null) {
      ScaffoldMessenger.of(context).clearSnackBars(); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先等待讀取或設定所有參數'), backgroundColor: Colors.orange));
      return;
    }

    if (_isProductB && (_acCouplingOffSoc == null || _acCouplingOnSoc == null)) {
      ScaffoldMessenger.of(context).clearSnackBars(); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('設備尚未完成 AC Coupling 參數讀取，請稍候重試'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true);
    try {
      String aaaStr = _offGridDischargeSoc!.toString().padLeft(3, '0');
      String bbbStr = _offGridRecoverySoc!.toString().padLeft(3, '0');
      String cccStr = _onGridDischargeSoc!.toString().padLeft(3, '0');
      String dddStr = _onGridRecoverySoc!.toString().padLeft(3, '0');
      
      String cmd;

      if (_isProductB) {
        String eeeStr = _acCouplingOffSoc!.toString().padLeft(3, '0');
        String fffStr = _acCouplingOnSoc!.toString().padLeft(3, '0');
        cmd = '^S029BATDS$aaaStr,$bbbStr,$cccStr,$dddStr,$eeeStr,$fffStr\r';
      } else {
        cmd = '^S021BATDS$aaaStr,$bbbStr,$cccStr,$dddStr\r';
      }

      await Supabase.instance.client.functions.invoke(
        'send-device-command',
        body: {'sn': widget.inverterSn, 'commands': [cmd]},
      );

      await logUserAction('更改電池參數', details: '針對設備 ${widget.inverterSn} 執行了 SOC 電位設定變更');

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SOC設定已發送'), backgroundColor: Colors.teal));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMsg(e)), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSendButton({required String label, required VoidCallback onPressed, required Color color}) {
    return SizedBox(
      height: 48, 
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    );
  }

  Widget _buildControlRow({
    required String title,
    required int? value, 
    required List<int> options,
    required String unit,
    required Function(int?) onChanged,
    Widget? trailingAction,
  }) {
    final safeValue = (value != null && options.contains(value)) ? value : null;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(safeValue), 
                    initialValue: safeValue,  
                    hint: Text('-- $unit', style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.bold)),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.teal),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                    ),
                    items: options.map((opt) => DropdownMenuItem(value: opt, child: Text('$opt $unit', style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.bold)))).toList(),
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
          if (trailingAction != null) ...[
            const SizedBox(width: 12),
            trailingAction,
          ]
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: AppBar(
        title: const Text('電池參數設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))]
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('充電設定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal)),
                      const Divider(color: Color(0xFFF1F5F9), height: 32),
                      _buildControlRow(
                        title: '最大市電充電電流',
                        value: _maxAcChargeCurrent,
                        options: _generateList(10, 100, 10),
                        unit: 'A',
                        onChanged: (v) => setState(() => _maxAcChargeCurrent = v!),
                        trailingAction: _buildSendButton(
                          label: '設定', 
                          color: Colors.teal, 
                          onPressed: _sendAcChargeCurrent
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))]
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SOC相關設定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal)),
                      const Divider(color: Color(0xFFF1F5F9), height: 32),
                      
                      Row(
                        children: [
                          const Icon(Icons.power_off_rounded, size: 18, color: Colors.blueAccent),
                          const SizedBox(width: 8),
                          const Text('無市電(Off-Grid)狀態', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                        ],
                      ), 
                      const SizedBox(height: 16),
                      _buildControlRow(
                        title: '電池截止放電 SOC',
                        value: _offGridDischargeSoc,
                        options: _generateList(0, 80, 5),
                        unit: '%',
                        onChanged: (v) => setState(() => _offGridDischargeSoc = v!),
                      ),
                      _buildControlRow(
                        title: '電池重新放電 SOC',
                        value: _offGridRecoverySoc,
                        options: _generateList(10, 80, 5),
                        unit: '%',
                        onChanged: (v) => setState(() => _offGridRecoverySoc = v!),
                      ),

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Divider(color: Color(0xFFF1F5F9)),
                      ),

                      Row(
                        children: [
                          const Icon(Icons.power_rounded, size: 18, color: Colors.orangeAccent),
                          const SizedBox(width: 8),
                          const Text('有市電(On-Grid)狀態', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                        ],
                      ), 
                      const SizedBox(height: 16),
                      _buildControlRow(
                        title: '電池截止放電 SOC',
                        value: _onGridDischargeSoc,
                        options: _generateList(5, 95, 5),
                        unit: '%',
                        onChanged: (v) => setState(() => _onGridDischargeSoc = v!),
                      ),
                      _buildControlRow(
                        title: '電池重新放電 SOC',
                        value: _onGridRecoverySoc,
                        options: _generateList(10, 100, 5),
                        unit: '%',
                        onChanged: (v) => setState(() => _onGridRecoverySoc = v!),
                      ),

                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: _buildSendButton(
                          label: '設定', 
                          color: Colors.teal, 
                          onPressed: _sendSocSettings
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.white.withValues(alpha: 0.6),
              child: const Center(child: CircularProgressIndicator(color: Colors.teal)),
            )
        ],
      ),
    );
  }
}