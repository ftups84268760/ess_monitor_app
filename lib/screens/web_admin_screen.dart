import 'dart:convert'; 
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'package:universal_html/html.dart' as html; 
import 'package:flutter/foundation.dart'; 
import 'package:mqtt_client/mqtt_client.dart';
import '../utils/mqtt_factory.dart';

import 'device_list_screen.dart'; 
import 'dashboard/inner_dashboard.dart'; 
import '../main.dart'; 
import '../utils/audit_logger.dart';

class WebAdminScreen extends StatefulWidget {
  const WebAdminScreen({super.key});

  @override
  State<WebAdminScreen> createState() => _WebAdminScreenState();
}

class _WebAdminScreenState extends State<WebAdminScreen> {
  int _selectedIndex = 0;
  String? _selectedDeviceDbId;
  bool _selectedDeviceIsOnline = false;
  String _selectedDeviceName = '';
  String _selectedDeviceSn = '';

  // 🎯 使用者身份與頭像狀態
  bool _isAdmin = false;
  bool _isRoot = false; // 🎯 新增：專門判斷是否為最高管理員(root)
  String _userRole = '一般使用者';
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile(); 

    if (GlobalDeviceState.deviceId != null) {
      _selectedDeviceDbId = GlobalDeviceState.deviceId;
      _selectedDeviceIsOnline = GlobalDeviceState.isOnline;
      _selectedDeviceName = GlobalDeviceState.customName;
      _selectedDeviceSn = GlobalDeviceState.sn;
    }
  }

  Future<void> _fetchUserProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('role, avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _userRole = data['role'] ?? '一般使用者';
          _isAdmin = _userRole.contains('管理員') || _userRole == 'admin';
          _isRoot = _userRole == '系統管理員(root)'; // 🎯 設定 Root 權限標記
          _avatarUrl = data['avatar_url'];
        });
      }
    } catch(e) {
      debugPrint('讀取使用者資料失敗: $e');
    }
  }

  @override
  void dispose() {
    if (_selectedDeviceDbId != null) {
      GlobalDeviceState.needsNarrowPush = true;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String userEmail = Supabase.instance.client.auth.currentUser?.email ?? '使用者帳號';

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            left: 250,
            top: 0,
            bottom: 0,
            right: 0,
            child: Container(
              color: (_selectedIndex == 1 || _selectedIndex == 2) ? Colors.white : Colors.grey.shade100,
              child: _buildRightPanelContent(), 
            ),
          ),
          
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 250,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Color(0xFF006400)],
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(8, 0)),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  const Text('FTESS Home網頁版', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 40),
                  ListTile(
                    leading: Icon(Icons.dashboard, color: _selectedIndex == 0 ? Colors.tealAccent : Colors.white),
                    title: Text('設備列表', style: TextStyle(color: _selectedIndex == 0 ? Colors.tealAccent : Colors.white)),
                    selected: _selectedIndex == 0,
                    selectedTileColor: Colors.white.withValues(alpha: 0.15),
                    onTap: () {
                      setState(() { 
                        _selectedIndex = 0; 
                        _selectedDeviceDbId = null; 
                        GlobalDeviceState.clear(); 
                      });
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.apps_rounded, color: _selectedIndex == 1 ? Colors.tealAccent : Colors.white),
                    title: Text('系統功能', style: TextStyle(color: _selectedIndex == 1 ? Colors.tealAccent : Colors.white)),
                    selected: _selectedIndex == 1,
                    selectedTileColor: Colors.white.withValues(alpha: 0.15),
                    onTap: () {
                      setState(() { _selectedIndex = 1; });
                    },
                  ),
                  // 🎯 權限判斷：只有管理員能看見「進階功能」選單
                  if (_isAdmin)
                    ListTile(
                      leading: Icon(Icons.settings_applications_rounded, color: _selectedIndex == 2 ? Colors.tealAccent : Colors.white),
                      title: Text('進階功能', style: TextStyle(color: _selectedIndex == 2 ? Colors.tealAccent : Colors.white)),
                      selected: _selectedIndex == 2,
                      selectedTileColor: Colors.white.withValues(alpha: 0.15),
                      onTap: () {
                        setState(() { _selectedIndex = 2; });
                      },
                    ),
                  const Spacer(), 
                  const Divider(color: Colors.white24, height: 1),
                  
                  ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white24,
                      backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                      child: _avatarUrl == null ? const Icon(Icons.person, size: 20, color: Colors.white) : null,
                    ),
                    title: Text(userEmail, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    subtitle: Text(_userRole, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text('登出系統', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    onTap: () async {
                      GlobalDeviceState.clear();
                      await logUserAction('登出', details: '使用者自 網頁版管理平台 登出');
                      await Supabase.instance.client.auth.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const RootScreen()),
                          (route) => false,
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanelContent() {
    if (_selectedIndex == 2 && _isAdmin) {
      return _buildAdvancedFeaturesView(); 
    }
    if (_selectedIndex == 1) {
      return _buildSystemSettingsView(); 
    }

    if (_selectedDeviceDbId != null) {
      return InnerDashboardNavigation(
        customInverterName: _selectedDeviceName,
        isInverterOnline: _selectedDeviceIsOnline,
        deviceDbId: _selectedDeviceDbId!,
        inverterSn: _selectedDeviceSn, 
        accountType: _userRole, 
      );
    } else {
      return DeviceListScreen(
        accountType: _userRole, 
        onSelectedInverterChanged: (String deviceDbId, bool isOnline, String customName, String sn) {
          setState(() {
            _selectedDeviceDbId = deviceDbId;
            _selectedDeviceIsOnline = isOnline;
            _selectedDeviceName = customName;
            _selectedDeviceSn = sn;
          });
        },
      );
    }
  }

  // 🎯 修改點：「系統功能」現在僅保留系統紀錄
  Widget _buildSystemSettingsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('系統功能', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 40),
          
          Wrap(
            spacing: 24, 
            runSpacing: 24, 
            children: [
              _buildSettingCard(
                title: '系統紀錄',
                subtitle: '匯出指定時段的設備運作數據',
                icon: Icons.history_edu_rounded,
                color: Colors.purple,
                onTap: () => _showExportLogsDialog(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🎯 新增：「進階功能」視圖，依據不同等級的管理員渲染卡片
  Widget _buildAdvancedFeaturesView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('進階功能', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 40),
          
          Wrap(
            spacing: 24, 
            runSpacing: 24, 
            children: [
              _buildSettingCard(
                title: '使用者操作紀錄',
                subtitle: '查詢全站使用者的操作紀錄',
                icon: Icons.manage_search_rounded,
                color: Colors.indigo,
                onTap: () => _showAuditLogsDialog(),
              ),
              // 🎯 Root 管理員專屬：管理員權限
              if (_isRoot)
                _buildSettingCard(
                  title: '管理員權限',
                  subtitle: '指派或撤銷系統管理員身分',
                  icon: Icons.admin_panel_settings_rounded,
                  color: Colors.blueAccent,
                  onTap: () => _showAdminPromotionDialog(),
                ),
              _buildSettingCard(
                title: '推播公告',
                subtitle: '發送重要營運通知或更新資訊',
                icon: Icons.campaign_rounded,
                color: Colors.orange,
                onTap: () => _showGlobalPushDialog(),
              ),
              _buildSettingCard(
                title: '遠端偵錯',
                subtitle: '遠端查詢逆變器狀態與參數',
                icon: Icons.terminal_rounded,
                color: Colors.teal,
                onTap: () => _showRemoteDiagnosticsDialog(),
              ),
              // 🎯 Root 管理員專屬：強制移轉所有權
              if (_isRoot)
                _buildSettingCard(
                  title: '設備所有權強制移轉',
                  subtitle: '強制轉移指定設備之所有權',
                  icon: Icons.gavel_rounded,
                  color: Colors.redAccent,
                  onTap: () => _showForceTransferDialog(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08), 
            blurRadius: 15, 
            offset: const Offset(0, 5), 
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent, 
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 32, color: color),
                ),
                const SizedBox(height: 24),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 8),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 以下為系統管理員專屬功能對話框 (只有 _isAdmin = true 才能點擊進入)
  // --------------------------------------------------------------------------
  void _showAuditLogsDialog() {
    final TextEditingController emailFilterController = TextEditingController();
    bool isLoading = true;
    bool isDownloading = false;
    List<dynamic> logs = [];
    bool isInitialized = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          Future<void> loadData() async {
            setDialogState(() => isLoading = true);
            try {
              var query = Supabase.instance.client
                  .from('user_activity_logs')
                  .select();

              final filterText = emailFilterController.text.trim();
              if (filterText.isNotEmpty) {
                query = query.ilike('user_email', '%$filterText%');
              }

              final data = await query.order('created_at', ascending: false).limit(1000);
              
              if (dialogContext.mounted) {
                setDialogState(() {
                  logs = data;
                  isLoading = false;
                });
              }
            } catch (e) {
              debugPrint('讀取日誌失敗: $e');
              if (dialogContext.mounted) {
                setDialogState(() => isLoading = false);
              }
            }
          }

          if (!isInitialized) {
            isInitialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadData();
            });
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.manage_search_rounded, color: Colors.indigo, size: 28),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('系統操作紀錄', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: isDownloading || logs.isEmpty ? null : () async {
                    setDialogState(() => isDownloading = true);
                    try {
                      List<String> headers = ['時間', '使用者帳號', '操作類型', '詳細內容'];
                      List<String> csvRows = [headers.join(',')];

                      for (var log in logs) {
                        final DateTime time = DateTime.parse(log['created_at']).toLocal();
                        final String timeStr = "${time.year}/${time.month.toString().padLeft(2,'0')}/${time.day.toString().padLeft(2,'0')} ${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}";
                        
                        String details = log['details']?.toString().replaceAll('"', '""') ?? '';
                        if (details.contains(',')) details = '"$details"';

                        csvRows.add([
                          timeStr,
                          log['user_email'],
                          log['action'],
                          details
                        ].join(','));
                      }

                      String csvContent = '\uFEFF${csvRows.join('\n')}'; 
                      final bytes = utf8.encode(csvContent);

                      if (kIsWeb) {
                        html.AnchorElement(href: html.Url.createObjectUrlFromBlob(html.Blob([bytes])))
                          ..setAttribute("download", "FTESS_系統操作紀錄.csv")
                          ..click();
                      }

                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 操作紀錄已成功匯出！'), backgroundColor: Colors.teal));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('匯出失敗: $e'), backgroundColor: Colors.redAccent));
                    } finally {
                      if (dialogContext.mounted) {
                        setDialogState(() => isDownloading = false);
                      }
                    }
                  },
                  icon: isDownloading 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                  label: const Text('匯出 CSV', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SizedBox(
              width: 800,
              height: 500,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: emailFilterController,
                          decoration: InputDecoration(
                            labelText: '搜尋條件',
                            hintText: '請輸入使用者帳號',
                            prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
                            isDense: true,
                          ),
                          onSubmitted: (_) => loadData(), 
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () => loadData(),
                        child: const Text('搜尋', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: isLoading 
                      ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
                      : logs.isEmpty
                        ? const Center(child: Text('查無任何操作紀錄', style: TextStyle(color: Colors.black54)))
                        : Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ListView.separated(
                                itemCount: logs.length,
                                separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.black12),
                                itemBuilder: (context, index) {
                                  final log = logs[index];
                                  final DateTime time = DateTime.parse(log['created_at']).toLocal();
                                  final String timeStr = "${time.year}/${time.month.toString().padLeft(2,'0')}/${time.day.toString().padLeft(2,'0')} ${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}";
                                  
                                  Color actionColor = Colors.grey;
                                  if (log['action'].toString().contains('登入') || log['action'].toString().contains('登出')) actionColor = Colors.teal;
                                  if (log['action'].toString().contains('設備') || log['action'].toString().contains('參數') || log['action'].toString().contains('電價')) actionColor = Colors.orange;
                                  if (log['action'].toString().contains('權限')) actionColor = Colors.blueAccent;
                                  if (log['action'].toString().contains('刪除') || log['action'].toString().contains('強制移轉')) actionColor = Colors.redAccent;

                                  return ListTile(
                                    tileColor: index.isEven ? Colors.white : Colors.grey.shade50,
                                    leading: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: actionColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: actionColor.withValues(alpha: 0.5)),
                                      ),
                                      child: Text(log['action'], style: TextStyle(color: actionColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                    title: Text(log['user_email'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    subtitle: Text(log['details'] ?? '', style: const TextStyle(color: Colors.black87, fontSize: 13)),
                                    trailing: Text(timeStr, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                  );
                                },
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('關閉', style: TextStyle(color: Colors.grey)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showAdminPromotionDialog() {
    final TextEditingController emailController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          Future<void> changeAdminRole(bool makeAdmin) async {
            final email = emailController.text.trim();
            if (email.isEmpty) {
              ScaffoldMessenger.of(context).clearSnackBars(); 
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請輸入欲設定的帳號信箱'), backgroundColor: Colors.orange));
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

            setDialogState(() => isProcessing = true);

            try {
              final rpcName = makeAdmin ? 'promote_to_admin_by_email' : 'demote_from_admin_by_email';
              final response = await Supabase.instance.client.rpc(
                rpcName,
                params: {'target_email': email},
              );

              if (!dialogContext.mounted || !mounted) return;

              if (response['success'] == true) {
                await logUserAction(
                  '權限變動', 
                  details: '將帳號 $email ${makeAdmin ? '升級為系統管理員' : '降級為一般使用者'}'
                );
                if (!dialogContext.mounted || !mounted) return;
                Navigator.pop(dialogContext); 
                ScaffoldMessenger.of(context).clearSnackBars(); 
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.teal));
              } else {
                ScaffoldMessenger.of(context).clearSnackBars(); 
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.redAccent));
              }
            } catch (e) {
              if (dialogContext.mounted && mounted) {
                ScaffoldMessenger.of(context).clearSnackBars(); 
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('發生錯誤: $e'), backgroundColor: Colors.redAccent));
              }
            } finally {
              if (dialogContext.mounted) setDialogState(() => isProcessing = false);
            }
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.admin_panel_settings_rounded, color: Colors.blueAccent, size: 28),
                SizedBox(width: 8),
                Text('管理員權限設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('升級權限，該帳號將獲得系統管理員權限；若撤銷權限，該帳號將恢復一般使用者權限。', style: TextStyle(fontSize: 12, color: Colors.blueAccent, height: 1.5)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: '輸入欲設定的帳號 (電子郵件)',
                      hintText: 'example@email.com',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blueAccent, width: 2)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isProcessing ? Colors.grey : Colors.redAccent)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0,
                ),
                onPressed: isProcessing ? null : () => changeAdminRole(false),
                child: const Text('撤銷權限', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: isProcessing ? null : () => changeAdminRole(true),
                child: isProcessing 
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('升級權限', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showGlobalPushDialog() {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController bodyController = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.campaign_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Text('發送全域推播', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: '公告標題',
                      hintText: '例如：系統維護通知',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: bodyController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: '公告內容',
                      hintText: '請輸入發送內容',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange, width: 2)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSending ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: isSending ? null : () async {
                  if (titleController.text.trim().isEmpty || bodyController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('標題與內容不能為空'), backgroundColor: Colors.redAccent));
                    return;
                  }

                  setDialogState(() => isSending = true);

                  try {
                    await Supabase.instance.client.functions.invoke(
                      'broadcast-notification', 
                      body: {
                        'title': titleController.text.trim(),
                        'body': bodyController.text.trim(),
                      }
                    );
                    
                    if (!dialogContext.mounted || !mounted) return;
                    Navigator.pop(dialogContext); 
                    
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系統公告已成功推播至所有裝置！'), backgroundColor: Colors.teal));
                  } catch (e) {
                    if (dialogContext.mounted) setDialogState(() => isSending = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('推播發送失敗: $e'), backgroundColor: Colors.redAccent));
                    }
                  }
                },
                child: isSending 
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('確認發送', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          );
        }
      ),
    );
  }

  void _showForceTransferDialog() {
    TextEditingController? snController;
    final TextEditingController emailController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.warning_rounded, color: Colors.redAccent, size: 28),
                SizedBox(width: 8),
                Text('設備所有權強制移轉', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.redAccent)),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '警告：此操作將無條件立即轉移指定設備之所有權至新帳號，並強制清除該設備的所有歷史分享紀錄。請謹慎操作！', 
                    style: TextStyle(fontSize: 13, color: Colors.redAccent, height: 1.5, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 20),
                  
                  Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                      try {
                        final res = await Supabase.instance.client
                            .from('devices')
                            .select('sn')
                            .ilike('sn', '%${textEditingValue.text}%')
                            .limit(10);
                        return (res as List).map((e) => e['sn'].toString());
                      } catch (e) {
                        return const Iterable<String>.empty();
                      }
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      snController = controller; 
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: '逆變器序號 (SN)',
                          hintText: '請輸入逆變器序號',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
                        ),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 418), 
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final String option = options.elementAt(index);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(option, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: '接收者帳號 (電子郵件)',
                      hintText: '請輸入接收者的註冊信箱',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: isProcessing ? null : () async {
                  final targetSn = snController?.text.trim() ?? '';
                  final targetEmail = emailController.text.trim();
                  
                  if (targetSn.isEmpty || targetEmail.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('序號與接收者帳號均不得為空'), backgroundColor: Colors.orange));
                    return;
                  }

                  setDialogState(() => isProcessing = true);

                  try {
                    final deviceData = await Supabase.instance.client
                        .from('devices')
                        .select('id')
                        .eq('sn', targetSn)
                        .maybeSingle();

                    if (!dialogContext.mounted || !mounted) return; 

                    if (deviceData == null) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('查無此設備序號，請重新確認'), backgroundColor: Colors.redAccent));
                       setDialogState(() => isProcessing = false);
                       return;
                    }

                    final int deviceId = deviceData['id'];

                    final response = await Supabase.instance.client.rpc(
                      'force_transfer_device_ownership',
                      params: {
                        'p_device_id': deviceId, 
                        'p_target_email': targetEmail
                      },
                    );

                    if (!dialogContext.mounted || !mounted) return; 

                    if (response['success'] == true) {
                      await logUserAction(
                        '強制移轉設備', 
                        details: '將設備 (SN: $targetSn) 強制移轉給 $targetEmail'
                      );
                      if (!dialogContext.mounted || !mounted) return;
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? '設備移轉成功！'), backgroundColor: Colors.teal));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? '設備移轉失敗'), backgroundColor: Colors.redAccent));
                      setDialogState(() => isProcessing = false);
                    }
                  } catch (e) {
                    if (dialogContext.mounted && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('發生錯誤: $e'), backgroundColor: Colors.redAccent));
                      setDialogState(() => isProcessing = false);
                    }
                  }
                },
                child: isProcessing 
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('強制移轉', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          );
        }
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 以下為「所有人皆可使用」，但「嚴格驗證擁有權」的功能對話框
  // --------------------------------------------------------------------------
  void _showExportLogsDialog() {
    DateTime startDate = DateTime.now().subtract(const Duration(days: 7));
    DateTime endDate = DateTime.now();
    bool isDownloading = false;
    TextEditingController? snController;
    DateTime? earliestDataDate; 

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.history_edu_rounded, color: Colors.purple, size: 28),
                SizedBox(width: 8),
                Text('匯出系統紀錄', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                      try {
                        if (_isAdmin) {
                          final res = await Supabase.instance.client
                              .from('devices')
                              .select('sn')
                              .ilike('sn', '%${textEditingValue.text}%')
                              .limit(10);
                          return (res as List).map((e) => e['sn'].toString());
                        } else {
                          final res = await Supabase.instance.client.rpc('get_accessible_devices');
                          return (res as List)
                              .map((e) => e['sn'].toString())
                              .where((sn) => sn.toLowerCase().contains(textEditingValue.text.toLowerCase()))
                              .take(10);
                        }
                      } catch (e) {
                        return const Iterable<String>.empty();
                      }
                    },
                    onSelected: (String selection) async {
                      try {
                        final earliestRes = await Supabase.instance.client
                            .from('telemetry_test')
                            .select('created_at')
                            .eq('device_id', selection)
                            .order('created_at', ascending: true)
                            .limit(1);
                            
                        if (earliestRes.isNotEmpty) {
                          String rawTime = earliestRes.first['created_at'].toString();
                          if (rawTime.length >= 19) {
                            setDialogState(() { earliestDataDate = DateTime.parse(rawTime.substring(0, 19)); });
                          }
                        }
                      } catch(e) {
                         debugPrint('查詢最早日期失敗');
                      }
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      snController = controller; 
                      focusNode.addListener(() async {
                         if (!focusNode.hasFocus && controller.text.isNotEmpty) {
                            try {
                              final earliestRes = await Supabase.instance.client
                                  .from('telemetry_test')
                                  .select('created_at')
                                  .eq('device_id', controller.text)
                                  .order('created_at', ascending: true)
                                  .limit(1);
                                  
                              if (earliestRes.isNotEmpty) {
                                String rawTime = earliestRes.first['created_at'].toString();
                                if (rawTime.length >= 19) {
                                  setDialogState(() { earliestDataDate = DateTime.parse(rawTime.substring(0, 19)); });
                                }
                              }
                            } catch(e) {
                              debugPrint('焦點離開時查詢最早日期失敗: $e');
                            }
                         }
                      });

                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: '逆變器序號 (SN)',
                          hintText: '請輸入逆變器序號',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.purple, width: 2)),
                        ),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 418), 
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final String option = options.elementAt(index);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(option, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: startDate,
                              firstDate: earliestDataDate ?? DateTime(2020),
                              lastDate: endDate,
                            );
                            if (picked != null) setDialogState(() => startDate = picked);
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: '起始日期',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('${startDate.year}/${startDate.month}/${startDate.day}', style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.0),
                        child: Icon(Icons.arrow_forward_rounded, color: Colors.black38, size: 16),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: endDate,
                              firstDate: startDate,
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) setDialogState(() => endDate = picked);
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: '結束日期',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('${endDate.year}/${endDate.month}/${endDate.day}', style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.table_chart_rounded, color: Colors.green, size: 20),
                        SizedBox(width: 8),
                        Text('匯出格式：.CSV', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isDownloading ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: isDownloading ? null : () async {
                  final targetSn = snController?.text.trim() ?? '';
                  if (targetSn.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請輸入逆變器序號'), backgroundColor: Colors.redAccent));
                    return;
                  }

                  setDialogState(() => isDownloading = true);

                  try {
                    if (!_isAdmin) {
                      final check = await Supabase.instance.client.rpc('get_accessible_devices');
                      if (!context.mounted) return; 
                      
                      final allowedSns = (check as List).map((e) => e['sn'].toString()).toList();
                      if (!allowedSns.contains(targetSn)) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('權限不足，您只能匯出擁有的設備紀錄'), backgroundColor: Colors.redAccent));
                        setDialogState(() => isDownloading = false);
                        return;
                      }
                    }

                    final startDay = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
                    final startIso = startDay.toIso8601String();
                    
                    final endDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
                    final endIso = endDay.toIso8601String();

                    Future<List<dynamic>> fetchAllPages(String tableName, String selectFields) async {
                      List<dynamic> allData = [];
                      int offset = 0;
                      const int limitSize = 1000;
                      bool hasMore = true;

                      while (hasMore) {
                        final chunk = await Supabase.instance.client
                            .from(tableName)
                            .select(selectFields)
                            .eq('device_id', targetSn)
                            .gte('created_at', startIso)
                            .lte('created_at', endIso)
                            .order('created_at', ascending: true)
                            .range(offset, offset + limitSize - 1); 

                        allData.addAll(chunk);
                        if (chunk.length < limitSize) {
                          hasMore = false; 
                        } else {
                          offset += limitSize; 
                        }
                      }
                      return allData;
                    }

                    final testData = await fetchAllPages(
                      'telemetry_test', 
                      'created_at, battery_voltage, battery_capacity, battery_current, ac_in_v_r, ac_in_v_s, ac_in_freq, ac_out_v_r, ac_out_v_s'
                    );

                    final invPsData = await fetchAllPages(
                      'telemetry_inv_ps', 
                      'created_at, solar1_input_power, solar2_input_power, ac_in_total_active_power, ac_out_total_active_power, ac_out_power_percentage'
                    );

                    Map<String, Map<String, dynamic>> combined = {};

                    void mergeData(List<dynamic> rows) {
                      for (var row in rows) {
                        String timeStr = row['created_at'].toString();
                        if (timeStr.length >= 16) {
                          String key = timeStr.substring(0, 16);
                          if (!combined.containsKey(key)) combined[key] = {'created_at': timeStr};
                          combined[key]!.addAll(row);
                        }
                      }
                    }

                    mergeData(testData);
                    mergeData(invPsData);

                    if (!dialogContext.mounted || !mounted) return;

                    if (combined.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('該區間無任何運作紀錄'), backgroundColor: Colors.orange));
                      setDialogState(() => isDownloading = false);
                      return;
                    }

                    List<String> headers = [
                      '時間', '電池電壓(V)', '電池容量(%)', '電池電流(A)',
                      'L1市電電壓(V)', 'L2市電電壓(V)', '市電頻率(Hz)',
                      'L1輸出電壓(V)', 'L2輸出電壓(V)',
                      'PV1輸入功率(W)', 'PV2輸入功率(W)',
                      '市電總輸入功率(W)', '總輸出功率(W)', '負載量(%)'
                    ];
                    
                    List<String> csvRows = [headers.join(',')];
                    var sortedKeys = combined.keys.toList()..sort();
                    
                    Map<String, String> lastValues = {};

                    for (var key in sortedKeys) {
                      var row = combined[key]!;
                      
                      String getValue(String colName) {
                        if (row[colName] != null && row[colName].toString().isNotEmpty) {
                          lastValues[colName] = row[colName].toString();
                        }
                        return lastValues[colName] ?? '';
                      }

                      String formattedTime = key.replaceAll('T', ' ');

                      csvRows.add([
                        formattedTime,
                        getValue('battery_voltage'),
                        getValue('battery_capacity'),
                        getValue('battery_current'),
                        getValue('ac_in_v_r'),
                        getValue('ac_in_v_s'),
                        getValue('ac_in_freq'),
                        getValue('ac_out_v_r'),
                        getValue('ac_out_v_s'),
                        getValue('solar1_input_power'),
                        getValue('solar2_input_power'),
                        getValue('ac_in_total_active_power'),
                        getValue('ac_out_total_active_power'),
                        getValue('ac_out_power_percentage')
                      ].join(','));
                    }

                    String csvContent = '\uFEFF${csvRows.join('\n')}';
                    final bytes = utf8.encode(csvContent);

                    if (kIsWeb) {
                      html.AnchorElement(
                        href: html.Url.createObjectUrlFromBlob(html.Blob([bytes]))
                      )
                        ..setAttribute("download", "FTESS_系統紀錄_$targetSn.csv")
                        ..click();
                    } else {
                      final base64Str = base64Encode(bytes);
                      final url = Uri.parse('data:text/csv;charset=utf-8;base64,$base64Str');
                      try {
                        await launchUrl(url, webOnlyWindowName: '_blank');
                      } catch (e) {
                        debugPrint('開啟下載失敗: $e');
                      }
                    }

                    if (!dialogContext.mounted || !mounted) return;
                    Navigator.pop(dialogContext);

                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('✅ 設備 $targetSn 的紀錄已成功下載！'), 
                      backgroundColor: Colors.teal,
                      duration: const Duration(seconds: 4),
                    ));

                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('匯出失敗: $e'), backgroundColor: Colors.redAccent));
                    }
                  } finally {
                    if (dialogContext.mounted) {
                      setDialogState(() => isDownloading = false);
                    }
                  }
                },
                child: isDownloading 
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('下載', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          );
        }
      ),
    );
  }

  void _showRemoteDiagnosticsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RemoteDiagnosticsDialog(isAdmin: _isAdmin), 
    );
  }
}

// --------------------------------------------------------------------------
// 獨立元件：遠端偵錯
// --------------------------------------------------------------------------
class RemoteDiagnosticsDialog extends StatefulWidget {
  final bool isAdmin; 
  const RemoteDiagnosticsDialog({super.key, required this.isAdmin});

  @override
  State<RemoteDiagnosticsDialog> createState() => _RemoteDiagnosticsDialogState();
}

class _RemoteDiagnosticsDialogState extends State<RemoteDiagnosticsDialog> {
  TextEditingController? _snController;
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  String _selectedFormat = 'Plaintext';
  String? _connectedSn;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isSending = false;
  
  bool _filterRoutine = true; 
  DateTime? _lastManualSendTime;
  
  final List<String> _terminalLines = [];
  MqttClient? _mqttClient;

  @override
  void initState() {
    super.initState();
    _appendToTerminal('[系統] 等待輸入逆變器序號並建立連線...');
  }

  @override
  void dispose() {
    _commandController.dispose();
    _scrollController.dispose();
    _mqttClient?.disconnect(); 
    super.dispose();
  }

  void _appendToTerminal(String message) {
    if (!mounted) return;
    final now = DateTime.now();
    final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
                      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _terminalLines.add('$timestamp $message');
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _connectToMqtt(String targetSn) async {
    if (targetSn.isEmpty) {
      _appendToTerminal('[系統] ⚠️ 請先輸入逆變器序號');
      return;
    }

    if (!widget.isAdmin) {
      try {
        final check = await Supabase.instance.client.rpc('get_accessible_devices');
        final allowedSns = (check as List).map((e) => e['sn'].toString()).toList();
        if (!allowedSns.contains(targetSn)) {
          _appendToTerminal('[系統] ❌ 權限不足，無法連線至非您擁有的設備');
          return;
        }
      } catch(e) {
        _appendToTerminal('[系統] ❌ 權限驗證失敗');
        return;
      }
    }

    if (_isConnected) {
      _mqttClient?.disconnect();
      setState(() => _isConnected = false);
    }

    setState(() {
      _isConnecting = true;
      _connectedSn = targetSn;
    });
    
    _appendToTerminal('[系統] 正在建立 MQTT 直連至設備 $targetSn...');

    final clientId = 'flutter_admin_${DateTime.now().millisecondsSinceEpoch}';
    
    _mqttClient = getMqttClient(clientId);

    _mqttClient!.logging(on: false);
    _mqttClient!.keepAlivePeriod = 60;
    
    final connMessage = MqttConnectMessage()
        .authenticateAs('FTESS', '84268760') 
        .withClientIdentifier(clientId)
        .startClean();
    _mqttClient!.connectionMessage = connMessage;

    try {
      await _mqttClient!.connect();
      if (_mqttClient!.connectionStatus!.state == MqttConnectionState.connected) {
        final topic = 'inverter/telemetry/$targetSn';
        _mqttClient!.subscribe(topic, MqttQos.atMostOnce);
        
        setState(() {
          _isConnected = true;
          _isConnecting = false;
        });
        _appendToTerminal('[系統] ✅ 已成功連線並訂閱主題: $topic');

        _mqttClient!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
          final recMess = c![0].payload as MqttPublishMessage;
          final payloadString = String.fromCharCodes(recMess.payload.message);
          
          bool isRoutine = payloadString.startsWith('^D107') || 
                           payloadString.startsWith('^D050') || 
                           payloadString.startsWith('^D119') ||
                           payloadString.startsWith('^D092') ||
                           payloadString.startsWith('^D102') ||
                           payloadString.startsWith('^D008') ||
                           payloadString.startsWith('^D037');
          
          bool isInGracePeriod = false;
          if (_lastManualSendTime != null) {
            final diff = DateTime.now().difference(_lastManualSendTime!);
            if (diff.inMilliseconds < 2500) {
              isInGracePeriod = true;
            }
          }

          if (_filterRoutine && isRoutine && !isInGracePeriod) {
            return; 
          }
          
          String prefix = (isRoutine && !isInGracePeriod) ? '[輪詢數據]' : '[指令回覆訊息]';
          _appendToTerminal('$prefix $payloadString');
        });
      }
    } catch (e) {
      _mqttClient?.disconnect();
      setState(() {
        _isConnecting = false;
        _isConnected = false;
      });
      _appendToTerminal('[系統] ❌ MQTT 連線失敗: $e');
    }
  }

  Future<void> _sendCommand() async {
    if (!_isConnected || _connectedSn == null) {
      _appendToTerminal('[系統] ⚠ 請先連線至逆變器，才能發送指令');
      return;
    }

    String cmd = _commandController.text.trim();
    if (cmd.isEmpty) return;

    final builder = MqttClientPayloadBuilder();

    if (_selectedFormat == 'Hex') {
      try {
        String cleanHex = cmd.replaceAll(RegExp(r'\s+'), '');
        if (cleanHex.length % 2 != 0) throw Exception('Hex 長度錯誤');
        
        List<int> bytes = [];
        for (int i = 0; i < cleanHex.length; i += 2) {
          bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
        }
        String hexString = String.fromCharCodes(bytes);
        builder.addString(hexString);
      } catch (e) {
        _appendToTerminal('[系統] ❌ Hex 格式解析失敗，請確認內容是否為十六進位');
        return;
      }
    } else {
      String parsedCmd = cmd.replaceAll('<cr>', '\r').replaceAll('\\r', '\r');
      
      if (!parsedCmd.endsWith('\r')) {
        parsedCmd += '\r';
      }
      
      List<int> bytes = utf8.encode(parsedCmd);
      String safePayload = String.fromCharCodes(bytes);
      builder.addString(safePayload);
    }

    _appendToTerminal('[發送指令] ${_commandController.text.trim()}');
    setState(() {
      _isSending = true;
      _lastManualSendTime = DateTime.now(); 
    });

    try {
      final commandTopic = 'inverter/command/$_connectedSn';
      _mqttClient!.publishMessage(commandTopic, MqttQos.atMostOnce, builder.payload!);
      
      _appendToTerminal('[系統] 📡 指令已透過 MQTT 直連發送，等待設備回傳...');
    } catch (e) {
      _appendToTerminal('[系統] ❌ MQTT 指令發送失敗: $e');
    } finally {
      setState(() => _isSending = false);
      _commandController.clear(); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.terminal_rounded, color: Colors.teal, size: 28),
          SizedBox(width: 8),
          Text('遠端偵錯控制台', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 650, 
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                      try {
                        if (widget.isAdmin) {
                          final res = await Supabase.instance.client
                              .from('devices')
                              .select('sn')
                              .ilike('sn', '%${textEditingValue.text}%')
                              .limit(10);
                          return (res as List).map((e) => e['sn'].toString());
                        } else {
                          final res = await Supabase.instance.client.rpc('get_accessible_devices');
                          return (res as List)
                              .map((e) => e['sn'].toString())
                              .where((sn) => sn.toLowerCase().contains(textEditingValue.text.toLowerCase()))
                              .take(10);
                        }
                      } catch (e) {
                        return const Iterable<String>.empty();
                      }
                    },
                    onSelected: (String selection) {
                      _connectToMqtt(selection);
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      _snController = controller; 
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !_isConnected && !_isConnecting,
                        decoration: InputDecoration(
                          labelText: '逆變器序號 (SN)',
                          hintText: '輸入並選擇以連線...',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.teal, width: 2)),
                        ),
                        onSubmitted: (val) => _connectToMqtt(val),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300), 
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(option, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? Colors.redAccent : Colors.teal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: _isConnecting ? null : () {
                    if (_isConnected) {
                      _mqttClient?.disconnect();
                      setState(() => _isConnected = false);
                      _appendToTerminal('[系統] 🛑 已手動中斷連線');
                    } else {
                      _connectToMqtt(_snController?.text.trim() ?? '');
                    }
                  },
                  icon: _isConnecting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Icon(_isConnected ? Icons.link_off_rounded : Icons.link_rounded, size: 18, color: Colors.white),
                  label: Text(_isConnected ? '斷開' : '連線', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _commandController,
                    enabled: _isConnected,
                    decoration: InputDecoration(
                      labelText: '發送指令',
                      hintText: _selectedFormat == 'Hex' ? '例如: 5E 50 30...' : '例如: ^P003WS',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.teal, width: 2)),
                    ),
                    onSubmitted: (_) => _sendCommand(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedFormat,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: ['Plaintext', 'Hex'].map((fmt) => DropdownMenuItem(value: fmt, child: Text(fmt, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (val) => setState(() => _selectedFormat = val!),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: (_isSending || !_isConnected) ? null : _sendCommand,
                  icon: _isSending 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  label: const Text('發送', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            ),
            
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: _filterRoutine,
                    activeColor: Colors.teal,
                    onChanged: (val) => setState(() => _filterRoutine = val ?? true),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('過濾背景輪詢數據 (僅顯示手動指令回覆)', style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 8),
            
            Container(
              width: double.infinity,
              height: 300,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E), 
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black87, width: 2),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _terminalLines.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: SelectableText(
                      _terminalLines[index],
                      style: const TextStyle(
                        fontFamily: 'Courier', 
                        color: Colors.greenAccent, 
                        fontSize: 13,
                        height: 1.4
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}