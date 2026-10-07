import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '/screens/scanner_screen.dart'; // 🎯 引入現有的掃描元件
import '../utils/audit_logger.dart';

String _getFriendlyErrorMsg(dynamic e) {
  final String errorMsg = e.toString();
  if (errorMsg.contains('SocketException') || errorMsg.contains('Failed host lookup')) {
    return '無法連線至雲端伺服器，請檢查您的 Wi-Fi 或網路連線狀態。';
  }
  return '錯誤細節: $errorMsg';
}

// ==========================================
// 設備資訊設定 (三標籤整合設計)
// ==========================================
class DeviceInfoSettingsScreen extends StatefulWidget {
  final String deviceDbId;
  final bool isRootOrOwner; 
  final String accountType; 
  
  const DeviceInfoSettingsScreen({
    super.key, 
    required this.deviceDbId, 
    required this.isRootOrOwner,
    required this.accountType,
  });

  @override
  State<DeviceInfoSettingsScreen> createState() => _DeviceInfoSettingsScreenState();
}

class _DeviceInfoSettingsScreenState extends State<DeviceInfoSettingsScreen> {
  final TextEditingController _snController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();

  final Map<String, List<String>> _taiwanLocations = {
    '基隆市': ['仁愛區', '信義區', '中正區', '中山區', '安樂區', '暖暖區', '七堵區'],
    '台北市': ['中正區', '大同區', '中山區', '松山區', '大安區', '萬華區', '信義區', '士林區', '北投區', '內湖區', '南港區', '文山區'],
    '新北市': ['板橋區', '三重區', '中和區', '永和區', '新莊區', '新店區', '樹林區', '鶯歌區', '三峽區', '淡水區', '汐止區', '瑞芳區', '土城區', '蘆洲區', '五股區', '泰山區', '林口區', '深坑區', '石碇區', '坪林區', '三芝區', '石門區', '八里區', '平溪區', '雙溪區', '貢寮區', '金山區', '萬里區', '烏來區'],
    '桃園市': ['桃園區', '中壢區', '大溪區', '楊梅區', '蘆竹區', '大園區', '龜山區', '八德區', '龍潭區', '平鎮區', '新屋區', '觀音區', '複興區'],
    '新竹市': ['東區', '北區', '香山區'],
    '新竹縣': ['竹北市', '竹東鎮', '新埔鎮', '關西鎮', '湖口鄉', '新豐鄉', '峨眉鄉', '寶山鄉', '北埔鄉', '芎林鄉', '橫山鄉', '尖石鄉', '五峰鄉'],
    '台中市': ['中區', '東區', '南區', '西區', '北區', '北屯區', '西屯區', '南屯區', '太平區', '大里區', '霧峰區', '烏日區', '豐原區', '后里區', '石岡區', '東勢區', '和平區', '新社區', '潭子區', '大雅區', '神岡區', '大肚區', '沙鹿區', '龍井區', '梧棲區', '清水區', '大甲區', '外埔區', '大安區'],
    '彰化縣': ['彰化市', '員林市', '鹿港鎮', '和美鎮', '北斗鎮', '溪湖鎮', '田中鎮', '二林鎮', '線西鄉', '伸港鄉', '福興鄉', '秀水鄉', '花壇鄉', '芬園鄉', '大村鄉', '埔鹽鄉', '埔心鄉', '永靖鄉', '社頭鄉', '二水鄉', '田尾鄉', '埤頭鄉', '芳苑鄉', '大城鄉', '竹塘鄉', '溪州鄉'],
    '南投縣': ['南投市', '埔里鎮', '草屯鎮', '竹山鎮', '集集鎮', '名間鄉', '鹿谷鄉', '中寮鄉', '魚池鄉', '國姓鄉', '水里鄉', '信義鄉', '仁愛鄉'],
    '雲林縣': ['斗六市', '斗南鎮', '虎尾鎮', '西螺鎮', '土庫鎮', '北港鎮', '古坑鄉', '大埤鄉', '莿桐鄉', '林內鄉', '二崙鄉', '崙背鄉', '麥寮鄉', '東勢鄉', '褒忠鄉', '臺西鄉', '元長鄉', '四湖鄉', '口湖鄉', '水林鄉'],
    '高雄市': ['鹽埕區', '鼓山區', '左營區', '楠梓區', '三民區', '新興區', '前金區', '苓雅區', '前鎮區', '旗津區', '小港區', '鳳山區', '林園區', '大寮區', '大樹區', '大社區', '仁武區', '鳥松區', '岡山區', '橋頭區', '燕巢區', '田寮區', '阿蓮區', '路竹區', '湖內區', '茄萣區', '永安區', '彌陀區', '梓官區', '旗山區', '美濃區', '六龜區', '甲仙區', '杉林區', '內門區', '態源區', '那瑪夏區'],
    '屏東縣': ['屏東市', '潮州鎮', '東港鎮', '恆春鎮', '萬丹鄉', '長治鄉', '麟洛鄉', '九如鄉', '里港鄉', '鹽埔鄉', '高樹鄉', '萬巒鄉', '內埔鄉', '竹田鄉', '新埤鄉', '枋寮鄉', '新園鄉', '崁頂鄉', '林邊鄉', '南州鄉', '佳冬鄉', '琉球鄉', '車城鄉', '滿州鄉', '枋山鄉', '三地門鄉', '霧臺鄉', '瑪家鄉', '泰武鄉', '來義鄉', '春日鄉', '獅子鄉', '牡丹鄉'],
    '宜蘭縣': ['宜蘭市', '羅東鎮', '蘇澳鎮', '頭城鎮', '礁溪鄉', '壯圍鄉', '員山鄉', '冬山鄉', '五結鄉', '三星鄉', '大同鄉', '南澳鄉'],
    '花蓮縣': ['花蓮市', '鳳林鎮', '玉里鎮', '新城鄉', '吉安鄉', '壽豐鄉', '光復鄉', '豐濱鄉', '瑞穗鄉', '富里鄉', '秀林鄉', '萬榮鄉', '卓溪鄉'],
    '台東縣': ['台東市', '成功鎮', '關山鎮', '卑南鄉', '大武鄉', '太麻里鄉', '東河鄉', '長濱鄉', '鹿野鄉', '池上鄉', '綠島鄉', '延平鄉', '海端鄉', '達仁鄉', '金峰鄉', '蘭嶼鄉']
  };

  String? _selectedCity;
  String? _selectedDistrict;
  bool _isSavingLocation = false;
  
  int _selectedTabIndex = 0; // 0: 逆變器, 1: 電池, 2: 安裝區域
  List<Map<String, dynamic>> _batteries = [];
  int _batteryPage = 0;
  bool _isLoadingBatteries = true;

  bool get _isAdmin => widget.accountType == '系統管理員(root)' || widget.accountType == '系統管理員' || widget.accountType == 'admin';

  @override
  void initState() {
    super.initState();
    _fetchExistingDeviceSpecs();
  }

  Future<void> _fetchExistingDeviceSpecs() async {
    try {
      if (widget.deviceDbId.isEmpty) return;

      final data = await Supabase.instance.client
          .from('devices')
          .select('sn, address, created_at')
          .eq('id', widget.deviceDbId)
          .single();

      _snController.text = data['sn'] ?? '';
      
      if (data['created_at'] != null) {
        DateTime dt = DateTime.parse(data['created_at']);
        _dateController.text = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
      } else {
        _dateController.text = "尚未紀錄";
      }

      String addr = data['address'] ?? '';
      for (var city in _taiwanLocations.keys) {
        if (addr.contains(city)) {
          _selectedCity = city;
          for (var dist in _taiwanLocations[city]!) {
            if (addr.contains(dist)) _selectedDistrict = dist;
          }
        }
      }
      
      _fetchBatteries();

    } catch (e) {
      if (mounted) setState(() { _dateController.text = "尚未紀錄"; _isLoadingBatteries = false; });
    }
  }

  Future<void> _fetchBatteries() async {
    if (_snController.text.isEmpty) return;
    setState(() => _isLoadingBatteries = true);
    try {
      final batData = await Supabase.instance.client
          .from('device_bat')
          .select('*')
          .eq('device_id', _snController.text) 
          .order('created_at', ascending: true);
          
      if (mounted) {
        setState(() {
          _batteries = List<Map<String, dynamic>>.from(batData);
          _isLoadingBatteries = false;
        });
      }
    } catch(e) {
      debugPrint('讀取電池失敗: $e');
      if (mounted) setState(() => _isLoadingBatteries = false);
    }
  }

  Future<void> _saveDeviceLocation() async {
    if (widget.deviceDbId.isEmpty || _selectedCity == null || _selectedDistrict == null) {
      ScaffoldMessenger.of(context).clearSnackBars(); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請選擇完整的縣市與行政區')));
      return;
    }

    setState(() { _isSavingLocation = true; });
    try {
      String fullAddress = "$_selectedCity$_selectedDistrict";
      await Supabase.instance.client.from('devices').update({
        'address': fullAddress,
      }).eq('id', widget.deviceDbId);

      await logUserAction('更改安裝區域', details: '將設備 ${_snController.text} 的安裝區域更改為: $fullAddress');

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('區域設定完成'), backgroundColor: Colors.teal));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMsg(e)), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() { _isSavingLocation = false; });
    }
  }

  Future<void> _deleteBattery(String batId, String batSn) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('電池模組移除確認'),
        content: Text('確定要移除電池模組 $batSn 嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('確定刪除', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    
    if (confirm != true) return;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      await Supabase.instance.client.from('device_bat').delete().eq('id', batId);
      await logUserAction('刪除電池模組', details: '從設備 ${_snController.text} 移除電池: $batSn');
      
      if (!mounted) return; 
      messenger.showSnackBar(const SnackBar(content: Text('電池模組已刪除'), backgroundColor: Colors.teal));
      _fetchBatteries(); 
    } catch(e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('刪除失敗: $e'), backgroundColor: Colors.redAccent));
    }
  }

  void _showAddBatteryDialog() {
    List<String> tempBats = [];
    final TextEditingController snController = TextEditingController();
    bool isSavingBat = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.4), 
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setDialogState) { 
          // 🎯 已移除 BackdropFilter，直接回傳 AlertDialog
          return AlertDialog(
            scrollable: true, 
            // 🎯 維持半透明背景 (稍微調升一點點不透明度至 0.85，確保文字閱讀性)
            backgroundColor: Colors.white.withValues(alpha: 0.95), 
            // 🎯 加回陰影讓視窗浮現出來，不與背景混淆
            elevation: 8, 
            insetPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.white, width: 1.5), 
            ),
            title: const Text('新增電池模組', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9, 
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: snController,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                    decoration: InputDecoration(
                      labelText: '電池模組序號(SN)',
                      labelStyle: const TextStyle(color: Colors.black54),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.7), 
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.camera_alt, color: Colors.black45),
                        onPressed: () async {
                          final String? scannedCode = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ScannerScreen()),
                          );

                          if (scannedCode != null && scannedCode.isNotEmpty) {
                            String cleanedCode = scannedCode.trim();
                            setDialogState(() {
                              snController.text = cleanedCode;
                            });
                          }
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.add, color: Colors.white, size: 20),
                    label: const Text('加入清單', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    onPressed: () {
                      final inputSn = snController.text.trim();
                      if (inputSn.isEmpty) return;
                      
                      // 🎯 關鍵修正 1：檢查是否已經存在於「已綁定的資料庫列表」中
                      final bool isAlreadyBound = _batteries.any((bat) => bat['bat_sn'] == inputSn);
                      if (isAlreadyBound) {
                        ScaffoldMessenger.of(stateContext).clearSnackBars();
                        ScaffoldMessenger.of(stateContext).showSnackBar(const SnackBar(
                          content: Text('此電池模組序號已綁定，請勿重複新增'),
                          backgroundColor: Colors.orange,
                        ));
                        return;
                      }

                      // 🎯 檢查 2：清單上限
                      if (tempBats.length >= 10) {
                        ScaffoldMessenger.of(stateContext).showSnackBar(const SnackBar(content: Text('一次最多只能新增10組電池模組')));
                        return;
                      }
                      
                      // 🎯 檢查 3：檢查是否已經存在於「下方的待存清單」中
                      if (tempBats.contains(inputSn)) {
                        ScaffoldMessenger.of(stateContext).showSnackBar(const SnackBar(content: Text('此序號已在清單中')));
                        return;
                      }
                      
                      // 檢查皆通過，加入清單並清空輸入框
                      setDialogState(() {
                        tempBats.add(inputSn);
                        snController.clear();
                      });
                    },
                  ),
                  
                  const Divider(height: 32, color: Colors.black12),
                  Text('待存清單 (${tempBats.length}/10)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 8),
                  
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5), 
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    child: tempBats.isEmpty 
                      ? const Center(child: Text('暫無資料，請掃描或手動輸入', style: TextStyle(color: Colors.black38)))
                      : ListView.builder(
                          itemCount: tempBats.length,
                          itemBuilder: (ctx, i) => ListTile(
                            dense: true,
                            leading: CircleAvatar(radius: 12, backgroundColor: Colors.teal, child: Text('${i+1}', style: const TextStyle(fontSize: 10, color: Colors.white))),
                            title: Text(tempBats[i], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 18),
                              onPressed: () => setDialogState(() => tempBats.removeAt(i)),
                            ),
                          )
                        ),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: isSavingBat ? null : () => Navigator.pop(dialogContext), child: const Text('取消', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal, 
                  elevation: 2,
                  // 🎯 關鍵修改：設定為圓角矩形，這裡以 10 的弧度為例，與上方的輸入框及清單保持一致
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10), 
                  ),
                ),
                onPressed: (isSavingBat || tempBats.isEmpty) ? null : () async {
                  setDialogState(() => isSavingBat = true);

                  final messenger = ScaffoldMessenger.of(context);
                  final nav = Navigator.of(dialogContext);

                  try {
                    final insertData = tempBats.map((sn) => {
                      'device_id': _snController.text, 
                      'bat_sn': sn
                    }).toList();
                    
                    await Supabase.instance.client.from('device_bat').insert(insertData);
                    
                    nav.pop(); 
                    
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(content: Text('成功新增 ${tempBats.length} 組電池模組'), backgroundColor: Colors.teal));
                    _fetchBatteries(); 
                  } catch(e) {
                    if (stateContext.mounted) {
                      setDialogState(() => isSavingBat = false);
                    }
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(content: Text('新增失敗: $e'), backgroundColor: Colors.redAccent));
                  }
                }, 
                child: isSavingBat 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                    : const Text('確認新增', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          );
        }
      )
    );
  }

  // 🎯 標籤頁 1：儲能逆變器
  Widget _buildInverterTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _snController,
          readOnly: true,
          style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: '產品序號(SN)',
            labelStyle: const TextStyle(color: Colors.teal),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _dateController,
          readOnly: true, 
          style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: '啟用日期',
            labelStyle: const TextStyle(color: Colors.teal),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  // 🎯 標籤頁 2：電池模組
  // 🎯 標籤頁 2：電池模組
  Widget _buildBatteryTab() {
    int totalPages = (_batteries.length / 5).ceil();
    if (totalPages == 0) totalPages = 1;
    
    if (_batteryPage >= totalPages) _batteryPage = totalPages - 1;
    if (_batteryPage < 0) _batteryPage = 0;

    final displayBats = _batteries.skip(_batteryPage * 5).take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('電池模組列表 (${_batteries.length})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 12), elevation: 0),
              icon: const Icon(Icons.add, size: 16, color: Colors.white),
              label: const Text('新增', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: widget.isRootOrOwner ? _showAddBatteryDialog : null, 
            )
          ],
        ),
        const SizedBox(height: 12),
        
        if (_isLoadingBatteries)
           const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: Colors.teal)))
        else if (_batteries.isEmpty)
           Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('目前尚未綁定任何電池模組', style: TextStyle(color: Colors.black38))))
        else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayBats.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.black12),
            itemBuilder: (context, index) {
              final bat = displayBats[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                // 🎯 替換這裡：改為真實產品圖片
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white, // 給予白色底，避免 PNG 透明處破圖
                    borderRadius: BorderRadius.circular(8), // 圓角設計
                    border: Border.all(color: Colors.black12), // 加上淡淡的邊框
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/bat_icon.png', // 您的自訂圖片檔名
                      fit: BoxFit.contain, // 使用 contain 確保機器全貌不被裁切
                    ),
                  ),
                ),
                title: const Text('FT-IFS-B05', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
                subtitle: Text('SN: ${bat['bat_sn']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                trailing: _isAdmin 
                    ? IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _deleteBattery(bat['id'], bat['bat_sn']))
                    : const SizedBox.shrink(), 
              );
            },
          ),
          
          if (_batteries.length > 5)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left, color: Colors.teal), onPressed: _batteryPage > 0 ? () => setState(() => _batteryPage--) : null),
                Text('${_batteryPage + 1} / $totalPages', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.chevron_right, color: Colors.teal), onPressed: _batteryPage < totalPages - 1 ? () => setState(() => _batteryPage++) : null),
              ],
            )
        ]
      ],
    );
  }

  // 🎯 標籤頁 3：安裝區域 (移入卡片內)
  Widget _buildLocationTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedCity,
          hint: const Text("請選擇所在縣市"),
          items: _taiwanLocations.keys.map((city) => DropdownMenuItem<String>(value: city, child: Text(city))).toList(),
          onChanged: (val) {
            setState(() {
              _selectedCity = val;
              _selectedDistrict = null;
            });
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.6),
            labelText: '縣/市'
          ),
        ),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          key: ValueKey(_selectedCity),
          initialValue: _selectedDistrict,
          hint: const Text("請選擇所在行政區"),
          items: (_selectedCity == null ? <String>[] : _taiwanLocations[_selectedCity]!)
              .map((dist) => DropdownMenuItem<String>(value: dist, child: Text(dist)))
              .toList(),
          onChanged: (val) => setState(() => _selectedDistrict = val),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.6),
            labelText: '行政區'
          ),
        ),
        
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 2),
            onPressed: _isSavingLocation 
                ? null 
                : (widget.isRootOrOwner ? _saveDeviceLocation : () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('權限不足，無法執行此功能'), backgroundColor: Colors.orange));
                  }),
            child: Text(_isSavingLocation ? '儲存中...' : '儲存變更', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: Colors.transparent, 
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0,
        title: const Text('設備資訊', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color:Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(child: Image.asset('assets/deviceinfo_full_bg.png', fit: BoxFit.cover)),
            
            SafeArea(
              bottom: false, 
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 100),
                    
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.65), 
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                          ),
                          child: Column(
                            children: [
                              Container(
                                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black12))),
                                child: Row(
                                  children: [
                                    // 🎯 標籤 1
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _selectedTabIndex = 0),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _selectedTabIndex == 0 ? Colors.teal : Colors.transparent, width: 3))),
                                          child: Text('儲能逆變器', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: _selectedTabIndex == 0 ? Colors.teal : Colors.black45, fontSize: 13)),
                                        ),
                                      ),
                                    ),
                                    // 🎯 標籤 2
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _selectedTabIndex = 1),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _selectedTabIndex == 1 ? Colors.teal : Colors.transparent, width: 3))),
                                          child: Text('電池模組', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: _selectedTabIndex == 1 ? Colors.teal : Colors.black45, fontSize: 13)),
                                        ),
                                      ),
                                    ),
                                    // 🎯 標籤 3 (新增)
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _selectedTabIndex = 2),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _selectedTabIndex == 2 ? Colors.teal : Colors.transparent, width: 3))),
                                          child: Text('安裝區域', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: _selectedTabIndex == 2 ? Colors.teal : Colors.black45, fontSize: 13)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: _selectedTabIndex == 0 
                                    ? _buildInverterTab() 
                                    : (_selectedTabIndex == 1 ? _buildBatteryTab() : _buildLocationTab()),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 40), 
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}