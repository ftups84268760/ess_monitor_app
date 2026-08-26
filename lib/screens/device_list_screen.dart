import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashboard/inner_dashboard.dart';
import 'w410s_provisioning_screen.dart';

class DeviceListScreen extends StatefulWidget {
  final Function(String, bool, String) onSelectedInverterChanged;
  const DeviceListScreen({super.key, required this.onSelectedInverterChanged});

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
      final response = await Supabase.instance.client.rpc('get_accessible_devices');
      return (response as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      debugPrint('抓取設備列表失敗: $e');
      return [];
    }
  }

  // 🎯 替換：呼叫全新的授權管理面板
  void _showManageSharesModal(dynamic deviceId, String deviceName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 允許內容自適應並被鍵盤推高
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
        title: const Text('修改逆變器名稱', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
            child: const Text('儲存修改', style: TextStyle(color: Colors.teal)),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('設備已成功移除'), backgroundColor: Colors.teal));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刪除設備失敗，請檢查雲端連線')));
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
          backgroundColor: Colors.grey[100],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('我的設備列表', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal, 
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const W410sProvisioningScreen(), 
            ),
          );
          _reloadDeviceList();
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              onChanged: (val) { setState(() {}); },
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜尋逆變器名稱、序號、安裝地點...',
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
                fillColor: const Color(0xFFF7F8F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[200]!),
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
          const SizedBox(height: 4),

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
                    return name.contains(query) || sn.contains(query) || address.contains(query);
                  }).toList();

                  displayList.sort((a, b) => _isAscending
                      ? a['name'].toString().compareTo(b['name'].toString())
                      : b['name'].toString().compareTo(a['name'].toString()));

                  if (displayList.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 100),
                        Center(
                          child: Text('查無符合條件的儲能設備。', style: TextStyle(color: Colors.black38, fontSize: 13)),
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: displayList.length,
                    itemBuilder: (context, index) {
                      final device = displayList[index];
                      final bool online = device['is_online'] ?? true;
                      final String deviceId = device['id'].toString();
                      
                      final bool isOwner = device['user_id'] == currentUserId;

                      Widget deviceCard = Card(
                        key: ValueKey(deviceId),
                        color: Colors.white,
                        elevation: 2,
                        margin: EdgeInsets.only(bottom: isOwner ? 0 : 10), 
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey[200]!)
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          leading: Stack(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(8),
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
                                  width: 9, height: 9,
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
                          title: Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(device['name'] ?? '未命名設備', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)
                                    ),
                                    if (!isOwner) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('來自共享', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                                      )
                                    ]
                                  ],
                                ),
                              ),
                              if (isOwner) ...[
                                IconButton(
                                  // 🎯 替換：改為呼叫全新底板
                                  icon: const Icon(Icons.share, size: 16, color: Colors.teal),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(6),
                                  onPressed: () => _showManageSharesModal(deviceId, device['name'] ?? ''),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 16, color: Colors.black26),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(6),
                                  onPressed: () => _editDeviceNameDialog(deviceId, device['name'] ?? ''),
                                )
                              ]
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('INV: ${device['sn'] ?? ''}', style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.w500)),
                              Text('DTU: ${device['dtu_sn'] ?? ''}', style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 12, color: Colors.teal),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      '${device['address'] ?? '尚未設定'}',
                                      style: TextStyle(
                                        color: (device['address'] == '尚未設定' || device['address'] == null) ? Colors.orangeAccent : Colors.teal,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.black26, size: 14),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => InnerDashboardNavigation(
                                  customInverterName: device['name'] ?? '未命名設備',
                                  isInverterOnline: online,
                                  deviceDbId: deviceId,
                                  inverterSn: device['sn']?.toString() ?? '未設定', 
                                ),
                              ),
                            );
                            _reloadDeviceList();
                          },
                        ),
                      );

                      if (isOwner) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Dismissible(
                            key: ValueKey('dismiss_$deviceId'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20.0),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.delete_sweep, color: Colors.white, size: 28),
                            ),
                            confirmDismiss: (direction) async {
                              return await showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('移除設備確認', style: TextStyle(fontWeight: FontWeight.bold)),
                                  content: Text('確定要將 「${device['name']}」 從雲端伺服器中永久移除嗎？\n(包含所有授權分享將一併失效)'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消', style: TextStyle(color: Colors.grey))),
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(true),
                                      child: const Text('確定移除', style: TextStyle(color: Colors.red)),
                                    )
                                  ],
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


// ============================================================================
// 🎯 全新實作：設備分享管理介面 (Bottom Sheet)
// 負責撈取清單、新增授權、刪除授權
// ============================================================================
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

  // 讀取已經分享的使用者清單
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

  // 新增分享
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
        FocusScope.of(context).unfocus(); // 關閉鍵盤
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.teal));
        await _fetchSharedUsers(); // 刷新清單
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      debugPrint('分享設備異常: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系統連線異常，請稍後再試'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  // 刪除分享 (B 帳號權限回收)
  Future<void> _removeShare(String shareId, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除授權確認', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('確定要取消分享給 $email 嗎？\n對方將立即失去檢視此設備的權限。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('確定移除', style: TextStyle(color: Colors.red))),
        ],
      )
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      // 透過 RLS 政策，擁有者可以直接刪除 device_shares 的紀錄
      await Supabase.instance.client.from('device_shares').delete().eq('id', shareId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已成功收回權限'), backgroundColor: Colors.teal));
      await _fetchSharedUsers();
    } catch (e) {
      debugPrint('刪除權限失敗: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // 動態高度，並在鍵盤彈出時往上推
      padding: EdgeInsets.only(
        top: 20, left: 16, right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20
      ),
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
          
          // 頂部：新增分享輸入區
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '請輸入欲分享設備的帳號電子信箱',
                    hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(height: 1, color: Colors.black12),
          ),
          
          const Text('已授權的帳號', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 10),

          // 底部：已授權清單 ListView
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
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey[200]!)
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          leading: CircleAvatar(
                            backgroundColor: Colors.teal.shade50,
                            child: const Icon(Icons.person, color: Colors.teal),
                          ),
                          title: Text(share['nickname'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          subtitle: Text(share['email'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.black54)),
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