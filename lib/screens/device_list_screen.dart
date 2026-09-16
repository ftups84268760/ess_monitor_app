import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashboard/inner_dashboard.dart';
import 'w410s_provisioning_screen.dart';

class DeviceListScreen extends StatefulWidget {
  final Function(String, bool, String) onSelectedInverterChanged;
  final String accountType;
  const DeviceListScreen({super.key, required this.onSelectedInverterChanged, required this.accountType});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> with WidgetsBindingObserver {
  bool _isAscending = true;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameInputController = TextEditingController();

  Key _builderKey = UniqueKey();
  RealtimeChannel? _realtimeChannel;
  String _filterMode = '全部'; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupRealtimeSubscription();
  }

  void _setupRealtimeSubscription() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _realtimeChannel = Supabase.instance.client
        .channel('public:devices')
        .onPostgresChanges(
          event: PostgresChangeEvent.update, 
          schema: 'public',
          table: 'devices',
          callback: (payload) {
            debugPrint('🔄 收到資料庫即時更新，自動重整畫面...');
            _reloadDeviceList(); 
          },
        )
        .subscribe();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadDeviceList();
    }
  }

  void _reloadDeviceList() {
    if (mounted) {
      setState(() {
        _builderKey = UniqueKey();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUserDevicesFromDatabase() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    try {
      final bool isAdmin = widget.accountType == '系統管理員' || widget.accountType == 'admin' || widget.accountType == '系統管理員(root)';
      
      if (isAdmin) {
        final response = await Supabase.instance.client.rpc('get_all_devices_admin');
        return (response as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
      } else {
        final response = await Supabase.instance.client.rpc('get_accessible_devices');
        return (response as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }
    } catch (e) {
      debugPrint('抓取設備列表失敗: $e');
      return [];
    }
  }

  Future<void> _toggleSharedPushNotification(String deviceId, bool currentValue) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final response = await Supabase.instance.client
          .from('device_shares')
          .update({'allow_notifications': !currentValue})
          .eq('device_id', int.parse(deviceId)) 
          .eq('shared_to_user_id', user.id)
          .select();

      if (response.isEmpty) {
        throw Exception('找不到對應的分享授權紀錄，或無權限修改');
      }
          
      _reloadDeviceList();

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); // 🎯 清空佇列
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentValue ? '已開啟該設備的推播通知' : '已關閉推播通知'),
            backgroundColor: !currentValue ? Colors.teal : Colors.black54,
            duration: const Duration(seconds: 2),
          )
        );
      }
    } catch (e) {
      debugPrint('切換推播失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); // 🎯 清空佇列
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('設定失敗: $e'), backgroundColor: Colors.redAccent)
        );
      }
    }
  }

  void _showManageSharesModal(dynamic deviceId, String deviceName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) => ManageSharesBottomSheet(
        deviceDbId: deviceId.toString(),
        deviceName: deviceName,
      ),
    );
  }

  void _editDeviceNameDialog(dynamic deviceId, String currentName) {
    _nameInputController.text = currentName;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('修改逆變器名稱', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
        content: TextField(
          controller: _nameInputController,
          decoration: const InputDecoration(
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.teal)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              final newName = _nameInputController.text.trim();
              if (newName.isEmpty) return;

              Navigator.pop(context);

              try {
                await Supabase.instance.client
                  .from('devices')
                  .update({'name': newName})
                  .eq('id', deviceId);
      
                _reloadDeviceList();
              } catch (e) {
                debugPrint('設備改名失敗: $e');
              }
            },
            child: const Text('儲存修改', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Future<void> _deleteDevice(dynamic deviceId) async {
    try {
      await Supabase.instance.client.from('devices').delete().eq('id', deviceId);

      _reloadDeviceList();

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); // 🎯 清空佇列
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('設備已成功移除'), backgroundColor: Colors.teal));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); // 🎯 清空佇列
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刪除設備失敗，請檢查雲端連線'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Widget _buildFilterChip(String label) {
    final bool isSelected = _filterMode == label;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ChoiceChip(
          label: SizedBox(
            width: double.infinity,
            child: Text(
              label, 
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
          selected: isSelected,
          selectedColor: Colors.teal,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: isSelected ? Colors.teal : Colors.grey.shade200)
          ),
          showCheckmark: false,
          onSelected: (bool selected) {
            if (selected) {
              setState(() {
                _filterMode = label;
              });
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final bool isAdmin = widget.accountType == '系統管理員' || widget.accountType == 'admin' || widget.accountType == '系統管理員(root)';

    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: AppBar(
        title: const Text('我的設備列表', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
            tooltip: '新增註冊設備',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const W410sProvisioningScreen(), 
                ),
              );
              _reloadDeviceList();
            },
          ),
          IconButton(
            icon: const Icon(Icons.get_app_rounded, color: Colors.teal), 
            tooltip: '輸入驗證碼接收設備',
            onPressed: () {
              showReceiveDeviceDialog(context, _reloadDeviceList);
            },
          ),
          IconButton(
            icon: Icon(_isAscending ? Icons.sort_by_alpha : Icons.sort, color: Colors.teal),
            onPressed: () {
              setState(() {
                _isAscending = !_isAscending;
              });
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))]
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) { setState(() {}); },
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: isAdmin ? '搜尋逆變器名稱、序號、地點或擁有者信箱...' : '搜尋逆變器名稱、序號、安裝地點...',
                  hintStyle: const TextStyle(color: Colors.black38, fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.teal, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16, color: Colors.black38),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip('全部'),
                _buildFilterChip('已連線'),
                _buildFilterChip('已離線'),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reloadDeviceList(),
              color: Colors.teal,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                key: _builderKey,
                future: _fetchUserDevicesFromDatabase(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)));
                  }

                  final List<Map<String, dynamic>> rawList = snapshot.data ?? [];

                  String query = _searchController.text.trim().toLowerCase();
                  List<Map<String, dynamic>> displayList = rawList.where((device) {
                    final bool online = device['is_online'] ?? true;
                    
                    if (_filterMode == '已連線' && !online) return false;
                    if (_filterMode == '已離線' && online) return false;

                    if (query.isEmpty) return true;
                    
                    final String name = (device['name'] ?? '').toString().toLowerCase();
                    final String sn = (device['sn'] ?? '').toString().toLowerCase();
                    final String address = (device['address'] ?? '').toString().toLowerCase();
                    
                    bool isMatch = name.contains(query) || sn.contains(query) || address.contains(query);

                    if (isAdmin) {
                      final String ownerEmail = (device['owner_email'] ?? '').toString().toLowerCase();
                      isMatch = isMatch || ownerEmail.contains(query);
                    }

                    return isMatch;
                  }).toList();

                  displayList.sort((a, b) => _isAscending
                      ? a['name'].toString().compareTo(b['name'].toString())
                      : b['name'].toString().compareTo(a['name'].toString()));

                  if (displayList.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 100),
                        Center(
                          child: Text('查無符合條件的設備。', style: TextStyle(color: Colors.black38, fontSize: 13)),
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: displayList.length,
                    itemBuilder: (context, index) {
                      final device = displayList[index];
                      final bool online = device['is_online'] ?? true;
                      final String deviceId = device['id'].toString();
                      
                      final bool isOwner = device['user_id'] == currentUserId;

                      Widget deviceCard = Container(
                        key: ValueKey(deviceId),
                        margin: EdgeInsets.only(bottom: isOwner ? 0 : 16), 
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))]
                        ),
                        child: Material( 
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => InnerDashboardNavigation(
                                    customInverterName: device['name'] ?? '未命名設備',
                                    isInverterOnline: online,
                                    deviceDbId: deviceId,
                                    inverterSn: device['sn']?.toString() ?? '未設定', 
                                    accountType: widget.accountType,
                                  ),
                                ),
                              );
                              _reloadDeviceList();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Stack(
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[50],
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: online ? Colors.teal.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Image.asset(
                                          'assets/images/inverter_icon.png',
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) => const Icon(
                                            Icons.developer_board_rounded,
                                            color: Colors.teal,
                                            size: 28
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 2, right: 2,
                                        child: Container(
                                          width: 10, height: 10,
                                          decoration: BoxDecoration(
                                            color: online ? Colors.green : Colors.red,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: (online ? Colors.green : Colors.red).withValues(alpha: 0.5),
                                                blurRadius: 4,
                                                spreadRadius: 1,
                                              )
                                            ],
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(device['name'] ?? '未命名設備', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis)
                                            ),
                                            if (!isOwner) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: (device['allow_notifications'] != null) ? Colors.orangeAccent.withValues(alpha: 0.15) : Colors.redAccent.withValues(alpha: 0.15), 
                                                  borderRadius: BorderRadius.circular(6)
                                                ),
                                                child: Text(
                                                    (device['allow_notifications'] != null) ? '來自共享' : '管理員檢視', 
                                                    style: TextStyle(color: (device['allow_notifications'] != null) ? Colors.orange : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)
                                                ),
                                              )
                                            ]
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text('INV: ${device['sn'] ?? ''}', style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w500)),
                                        ),
                                        const SizedBox(height: 2),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text('DTU: ${device['dtu_sn'] ?? ''}', style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w500)),
                                        ),
                                        
                                        if (isAdmin) ...[
                                          const SizedBox(height: 6),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.person_pin_circle, size: 14, color: Colors.orange),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment: Alignment.centerLeft,
                                                  child: Text(
                                                    '擁有者: ${device['owner_email'] ?? device['user_id'] ?? '未知'}',
                                                    style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                                                    maxLines: 1,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.location_on_outlined, size: 14, color: Colors.teal),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                '${device['address'] ?? '尚未設定'}',
                                                style: TextStyle(
                                                  color: (device['address'] == '尚未設定' || device['address'] == null) ? Colors.orangeAccent : Colors.teal,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (isOwner)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              borderRadius: BorderRadius.circular(20),
                                              onTap: () => _showManageSharesModal(deviceId, device['name'] ?? ''),
                                              child: const Padding(
                                                padding: EdgeInsets.all(6.0),
                                                child: Icon(Icons.share, size: 18, color: Colors.teal),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            InkWell(
                                              borderRadius: BorderRadius.circular(20),
                                              onTap: () => _editDeviceNameDialog(deviceId, device['name'] ?? ''),
                                              child: const Padding(
                                                padding: EdgeInsets.all(6.0),
                                                child: Icon(Icons.edit, size: 18, color: Colors.black26),
                                              ),
                                            )
                                          ],
                                        )
                                      else if (device['allow_notifications'] != null)
                                        IconButton(
                                          icon: Icon(
                                            (device['allow_notifications'] == true) ? Icons.notifications_active : Icons.notifications_off_outlined,
                                            color: (device['allow_notifications'] == true) ? Colors.teal : Colors.black38,
                                            size: 22,
                                          ),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(4),
                                          onPressed: () => _toggleSharedPushNotification(deviceId, device['allow_notifications'] == true),
                                        )
                                      else
                                        const SizedBox(height: 38), 
                                      
                                      const Padding(
                                        padding: EdgeInsets.only(top: 24.0, right: 8.0),
                                        child: Icon(Icons.arrow_forward_ios, color: Colors.black26, size: 16),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      );

                      if (isOwner) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16), 
                          child: Dismissible(
                            key: ValueKey('dismiss_$deviceId'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20.0),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.delete_sweep, color: Colors.white, size: 32),
                            ),
                            confirmDismiss: (direction) async {
                              return await showDialog(
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
                                    title: const Text('移除設備確認', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                                    content: Text('確定要將 「${device['name']}」 從雲端伺服器中永久移除嗎？\n(包含所有授權分享將一併失效)', style: const TextStyle(color: Colors.white70, height: 1.5, fontSize: 13)),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(true),
                                        child: const Text('確定移除', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                      )
                                    ],
                                  ),
                                ),
                              );
                            },
                            onDismissed: (direction) {
                              _deleteDevice(deviceId);
                            },
                            child: deviceCard,
                          ),
                        );
                      } else {
                        return deviceCard;
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ManageSharesBottomSheet extends StatefulWidget {
  final String deviceDbId;
  final String deviceName;

  const ManageSharesBottomSheet({super.key, required this.deviceDbId, required this.deviceName});

  @override
  State<ManageSharesBottomSheet> createState() => _ManageSharesBottomSheetState();
}

class _ManageSharesBottomSheetState extends State<ManageSharesBottomSheet> {
  bool _isLoading = true;
  bool _isAdding = false;
  List<Map<String, dynamic>> _sharedUsers = [];
  final TextEditingController _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSharedUsers();
  }

  Future<void> _fetchSharedUsers() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'get_device_shared_users',
        params: {'target_device_id': int.parse(widget.deviceDbId)},
      );
      if (mounted) {
        setState(() {
          _sharedUsers = (response as List).map((e) => Map<String, dynamic>.from(e)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('取得分享清單失敗: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addShare() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isAdding = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'share_device_by_email',
        params: {
          'target_email': email,
          'target_device_id': int.parse(widget.deviceDbId),
        }
      );

      if (!mounted) return;
      
      if (response['success'] == true) {
        _emailController.clear();
        FocusScope.of(context).unfocus(); 
        ScaffoldMessenger.of(context).clearSnackBars(); // 🎯 清空佇列
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.teal));
        await _fetchSharedUsers(); 
      } else {
        ScaffoldMessenger.of(context).clearSnackBars(); // 🎯 清空佇列
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      debugPrint('分享設備異常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); // 🎯 清空佇列
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系統連線異常，請稍後再試'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _removeShare(String shareId, String email) async {
    final confirm = await showDialog<bool>(
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
          title: const Text('移除授權確認', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
          content: Text('確定要取消分享給 $email 嗎？\n對方將立即失去檢視此設備的權限。', style: const TextStyle(color: Colors.white70, height: 1.5, fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消', style: TextStyle(color: Colors.grey))),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('確定移除', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
          ],
        ),
      )
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.from('device_shares').delete().eq('id', shareId);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); // 🎯 清空佇列
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已成功收回權限'), backgroundColor: Colors.teal));
      }
      await _fetchSharedUsers();
    } catch (e) {
      debugPrint('刪除權限失敗: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20, left: 16, right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20
      ),
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('管理「${widget.deviceName}」分享授權', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close, color: Colors.black45), onPressed: () => Navigator.pop(context))
            ],
          ),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '請輸入欲分享設備的帳號(電子信箱)',
                    hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0
                ),
                onPressed: _isAdding ? null : _addShare,
                child: _isAdding 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('新增', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: Divider(height: 1, color: Colors.black12),
          ),
          
          const Text('已授權的帳號', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 12),

          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.teal))
              : _sharedUsers.isEmpty
                ? const Center(child: Text('目前尚未分享給任何帳號', style: TextStyle(color: Colors.black38, fontSize: 13)))
                : ListView.builder(
                    itemCount: _sharedUsers.length,
                    itemBuilder: (context, index) {
                      final share = _sharedUsers[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))]
                        ),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: Colors.teal.withValues(alpha: 0.1),
                            child: const Icon(Icons.person, color: Colors.teal),
                          ),
                          title: Text(share['nickname'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                          subtitle: Text(share['email'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                            onPressed: () => _removeShare(share['share_id'], share['email']),
                          ),
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}

void showReceiveDeviceDialog(BuildContext context, VoidCallback onSuccessRefresh) {
  final TextEditingController codeController = TextEditingController();
  bool isProcessing = false;

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.3), 
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          backgroundColor: Colors.black87, 
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.get_app_rounded, color: Colors.tealAccent),
              SizedBox(width: 8),
              Text('接收設備', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('請輸入原設備擁有者提供給您的 6 位數接收碼。', style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 8, color: Colors.tealAccent),
                decoration: const InputDecoration(
                  counterText: "",
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: isProcessing 
                ? null 
                : () async {
                    final code = codeController.text.trim();
                    if (code.length != 6) return;

                    setState(() => isProcessing = true);

                    try {
                      final response = await Supabase.instance.client.rpc(
                        'accept_device_transfer',
                        params: {'p_code': code},
                      );

                      if (!dialogContext.mounted) return;

                      if (response['success'] == true) {
                        Navigator.pop(dialogContext); 
                        ScaffoldMessenger.of(context).clearSnackBars(); // 🎯 清空佇列
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.teal));
                        onSuccessRefresh(); 
                      } else {
                        ScaffoldMessenger.of(context).clearSnackBars(); // 🎯 清空佇列
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.redAccent));
                        setState(() => isProcessing = false);
                      }
                    } catch (e) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(context).clearSnackBars(); // 🎯 清空佇列
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('錯誤細節: ${e.toString()}'), backgroundColor: Colors.redAccent));
                        setState(() => isProcessing = false);
                      }
                    }
                  },
              child: isProcessing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black87, strokeWidth: 2)) : const Text('確認接收', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            )
          ],
        );
      }
    )
  );
}