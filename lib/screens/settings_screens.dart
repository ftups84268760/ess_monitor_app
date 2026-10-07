import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:ui';

import '../core/constants.dart';
import 'tou_settings_screen.dart';
// 🎯 引入 Logger
import '../utils/audit_logger.dart';

// 🎯 引入拆分出來的新檔案
import 'device_info_settings_screen.dart';
import 'advanced_settings_screens.dart';

// 🎯 全域共用的網路異常訊息轉換器
String _getFriendlyErrorMsg(dynamic e) {
  final String errorMsg = e.toString();
  if (errorMsg.contains('SocketException') || errorMsg.contains('Failed host lookup')) {
    return '無法連線至雲端伺服器，請檢查您的 Wi-Fi 或網路連線狀態。';
  }
  return '錯誤細節: $errorMsg';
}

// ==========================================
// 1. 設定主選單
// ==========================================
class SettingsSubMenuScreen extends StatefulWidget {
  final String deviceDbId;
  final String? accountType;
  final String? inverterSn; 
  const SettingsSubMenuScreen({super.key, required this.deviceDbId, this.accountType, this.inverterSn});

  @override
  State<SettingsSubMenuScreen> createState() => _SettingsSubMenuScreenState();
}

class _SettingsSubMenuScreenState extends State<SettingsSubMenuScreen> {
  bool _isLoading = true;
  bool _hasPermission = false;
  bool _isRootOrOwner = false;

  @override
  void initState() {
    super.initState();
    _checkUserPermission();
  }

  Future<void> _checkUserPermission() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final data = await Supabase.instance.client
          .from('devices')
          .select('user_id')
          .eq('id', widget.deviceDbId)
          .single();

      final bool isOwner = data['user_id'] == user.id;
      final bool isRoot = widget.accountType == '系統管理員(root)';
      final bool isAdmin = widget.accountType == 'admin' || widget.accountType == '系統管理員' || isRoot;

      if (mounted) {
        setState(() {
          _hasPermission = isOwner || isAdmin;
          _isRootOrOwner = isOwner || isRoot; 
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isRoot = widget.accountType == '系統管理員(root)';

    return Scaffold(
      extendBodyBehindAppBar: true, 
      extendBody: true, 
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('系統設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
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
              child: _isLoading 
                  ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                      children: [
                        _buildSubMenuTile(context, Icons.tsunami_outlined, '惡劣天氣預測', WeatherForecastScreen(deviceDbId: widget.deviceDbId, isRootOrOwner: _isRootOrOwner)),
                        _buildSubMenuTile(context, Icons.schedule, '時間電價(TOU)排程', TouSettingsScreen(deviceDbId: widget.deviceDbId, isRootOrOwner: _isRootOrOwner)),
                        _buildSubMenuTile(context, Icons.hourglass_bottom_rounded, '電價方案', ElectricityTariffScreen(deviceDbId: widget.deviceDbId, isRootOrOwner: _isRootOrOwner)),
                        
                        _buildSubMenuTile(context, Icons.developer_board, '設備資訊', DeviceInfoSettingsScreen(
                          deviceDbId: widget.deviceDbId, 
                          isRootOrOwner: _isRootOrOwner,
                          accountType: widget.accountType ?? '一般使用者',
                        )),
                        
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(color: Colors.black12, height: 1),
                        ),
                        
                        _buildSubMenuTile(
                          context, 
                          Icons.tune_rounded, 
                          '進階設定', 
                          DeviceAdvancedSettingsScreen(
                            deviceDbId: widget.deviceDbId, 
                            inverterSn: widget.inverterSn ?? '', 
                            isRootOrOwner: _isRootOrOwner,
                            isRoot: isRoot,
                          )
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMenuTile(BuildContext context, IconData icon, String title, Widget? targetScreen) {
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
                color: Colors.white.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Icon(icon, color: Colors.teal),
                title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black26),
                onTap: () {
                  if (!_hasPermission) {
                    ScaffoldMessenger.of(context).clearSnackBars(); 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('無此修改權限，僅設備擁有者可進入設定。'),
                      backgroundColor: Colors.redAccent,
                      duration: Duration(seconds: 2),
                    ));
                    return;
                  }
                  if (targetScreen != null) {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => targetScreen));
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. 系統推播通知設定
// ==========================================
class PushNotificationSettingsScreen extends StatefulWidget {
  final String deviceDbId;
  const PushNotificationSettingsScreen({super.key, required this.deviceDbId});

  @override
  State<PushNotificationSettingsScreen> createState() => _PushNotificationSettingsScreenState();
}

class _PushNotificationSettingsScreenState extends State<PushNotificationSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  bool gridOff = true;
  bool batteryFull = true;
  bool batteryLow = true;
  bool noPv = false;
  bool loadFull = true;
  bool loadOverload = true;

  @override
  void initState() {
    super.initState();
    _fetchNotificationSettings();
  }

  Future<void> _updateMasterToggle(bool enabled) async {
    setState(() {
      GlobalState.isPushNotificationEnabled = enabled;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('push_notifications_enabled', enabled);

      if (user != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({'push_notifications_enabled': enabled})
            .eq('id', user.id);
      }
    } catch (e) {
      debugPrint('全域推播狀態儲存失敗: $e');
    }
  }

  Future<void> _fetchNotificationSettings() async {
    try {
      if (widget.deviceDbId.isEmpty) return;

      final data = await Supabase.instance.client
          .from('devices')
          .select('notification_settings')
          .eq('id', widget.deviceDbId)
          .single();

      final settings = data['notification_settings'];
      if (settings != null && settings is Map && mounted) {
        setState(() {
          gridOff = settings['grid_off'] ?? true;
          batteryFull = settings['battery_full'] ?? true;
          batteryLow = settings['battery_low'] ?? true;
          noPv = settings['no_pv'] ?? false;
          loadFull = settings['load_full'] ?? true;
          loadOverload = settings['load_overload'] ?? true;
        });
      }
    } catch (e) {
      debugPrint('讀取推播設定異常 (套用預設值): $e'); 
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveNotificationSettings() async {
    if (widget.deviceDbId.isEmpty) return;
    setState(() => _isSaving = true);

    final Map<String, dynamic> newSettings = {
      'grid_off': gridOff,
      'battery_full': batteryFull,
      'battery_low': batteryLow,
      'no_pv': noPv,
      'load_full': loadFull,
      'load_overload': loadOverload,
    };

    try {
      await Supabase.instance.client.from('devices').update({
        'notification_settings': newSettings,
      }).eq('id', widget.deviceDbId);

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('設定完成'),
          backgroundColor: Colors.teal,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_getFriendlyErrorMsg(e)),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMasterEnabled = GlobalState.isPushNotificationEnabled;

    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: AppBar(
        title: const Text('系統推播通知條件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)))
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))]
                  ),
                  child: SwitchListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    secondary: const Icon(Icons.notifications_active, color: Colors.teal),
                    title: const Text('允許所有系統推播通知', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                    subtitle: const Text('關閉後將暫停接收所有警告與提示', style: TextStyle(fontSize: 11, color: Colors.black45)),
                    activeThumbColor: Colors.white,
                    activeTrackColor: Colors.teal,
                    value: isMasterEnabled,
                    onChanged: (bool value) => _updateMasterToggle(value),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                const Padding(
                  padding: EdgeInsets.only(left: 4.0, bottom: 12.0),
                  child: Text('細項條件設定(需開啟「允許所有系統推播通知」)', style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold)),
                ),

                Opacity(
                  opacity: isMasterEnabled ? 1.0 : 0.5,
                  child: IgnorePointer(
                    ignoring: !isMasterEnabled,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))]
                      ),
                      child: Column(
                        children: [
                          _buildSwitchTile('⚡ 市電停電 / 復電', '當電網斷電或恢復供電時，發送即時狀態推播', gridOff, (v) => setState(() => gridOff = v)),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          _buildSwitchTile('🔋 電池容量已滿 (100%)', '當儲能電池充飽電達 100% 時', batteryFull, (v) => setState(() => batteryFull = v)),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          _buildSwitchTile('🪫 電池容量低電位 (>20%)', '當電池剩餘電量低於 20% 安全儲備時', batteryLow, (v) => setState(() => batteryLow = v)),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          _buildSwitchTile('☀️ 無太陽能發電', '當太陽能發電功率降至 0 W 時', noPv, (v) => setState(() => noPv = v)),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          _buildSwitchTile('🏠 負載滿載', '當負載接近逆變器額定功率時', loadFull, (v) => setState(() => loadFull = v)),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          _buildSwitchTile('⚠️ 負載過載', '當負載超越逆變器最大容許功率時', loadOverload, (v) => setState(() => loadOverload = v)),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isMasterEnabled ? Colors.teal : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: (_isSaving || !isMasterEnabled) ? null : _saveNotificationSettings,
                  child: Text(_isSaving ? '儲存中...' : '儲存設定', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      dense: true,
      activeThumbColor: Colors.white,
      activeTrackColor: Colors.teal,
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black45)),
      value: value,
      onChanged: onChanged,
    );
  }
}

// ==========================================
// 3. 電價方案設定
// ==========================================
class ElectricityTariffScreen extends StatefulWidget {
  final String deviceDbId;
  final bool isRootOrOwner; 
  const ElectricityTariffScreen({super.key, required this.deviceDbId, required this.isRootOrOwner});

  @override
  State<ElectricityTariffScreen> createState() => _ElectricityTariffScreenState();
}

class _ElectricityTariffScreenState extends State<ElectricityTariffScreen> {
  final List<String> _tariffOptions = [
    '一般累進表燈(住商)',
    '簡易型(二段式)',
    '簡易型(三段式)',
    '標準型(二段式)',
    '標準型(三段式)',
  ];

  String _selectedTariff = '一般累進表燈(住商)';
  double _customRate = 3.5;
  final TextEditingController _rateController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchCurrentTariff();
  }

  Future<void> _fetchCurrentTariff() async {
    try {
      if (widget.deviceDbId.isEmpty) return;

      final data = await Supabase.instance.client
          .from('devices')
          .select('electricity_tariff, custom_tariff_rate')
          .eq('id', widget.deviceDbId)
          .single();

      if (mounted) {
        setState(() {
          _selectedTariff = data['electricity_tariff'] ?? '一般累進表燈(住商)';
          _customRate = double.tryParse((data['custom_tariff_rate'] ?? 3.5).toString()) ?? 3.5;
          _rateController.text = _customRate.toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMsg(e)), backgroundColor: Colors.redAccent));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveTariffToSupabase() async {
    if (widget.deviceDbId.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      Map<String, dynamic> updateData = {
        'electricity_tariff': _selectedTariff,
      };
      
      if (_selectedTariff == '一般累進表燈(住商)') {
        double parsedRate = double.tryParse(_rateController.text) ?? 3.5;
        updateData['custom_tariff_rate'] = parsedRate;
      }

      await Supabase.instance.client.from('devices').update(updateData).eq('id', widget.deviceDbId);

      // 🎯 紀錄: 變更電價方案
      await logUserAction('更改電價方案', details: '變更為「$_selectedTariff」');

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('設定完成'), backgroundColor: Colors.teal));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMsg(e)), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildTariffDetailNotice(String option) {
    String title = '';
    String content = '';

    if (option == '簡易型(二段式)') {
      title = '【簡易型(二段式)】時段電價說明：';
      content = '📅 夏月 (6/1 ~ 9/30)\n'
                '• 週一～週五：\n   - 00:00~09:00 離峰時段：電價 2.06 元/kWh\n   - 09:00~24:00 尖峰時段：電價 5.16 元/kWh\n'
                '• 週六、週日：\n   - 00:00~24:00 離峰時段：電價 2.06 元/kWh\n\n'
                '❄️ 非夏月 (夏月以外時間)\n'
                '• 週一～週五：\n   - 00:00~06:00、11:00~14:00 離峰時段：電價 1.99 元/kWh\n   - 06:00~11:00、14:00~24:00 尖峰時段：電價 4.93 元/kWh\n'
                '• 週六、週日：\n   - 00:00~24:00 離峰時段：電價 1.99 元/kWh';
    } else if (option == '簡易型(三段式)') {
      title = '【簡易型(三段式)】時段電價說明：';
      content = '📅 夏月 (6/1 ~ 9/30)\n'
                '• 週一～週五：\n   - 00:00~09:00 離峰時段：電價 2.06 元/kWh\n   - 09:00~16:00 半尖峰時段：電價 4.69 元/kWh\n   - 16:00~24:00 尖峰時段：電價 7.13 元/kWh\n'
                '• 週六、週日：\n   - 00:00~24:00 離峰時段：電價 2.06 元/kWh\n\n'
                '❄️ 非夏月 (夏月以外時間)\n'
                '• 週一～週五：\n   - 00:00~06:00、11:00~14:00 離峰時段：電價 1.99 元/kWh\n   - 06:00~11:00、14:00~24:00 半尖峰時段：電價 4.48 元/kWh\n'
                '• 週六、週日：\n   - 00:00~24:00 離峰時段：電價 1.99 元/kWh';
    } else if (option == '標準型(二段式)') {
      title = '【標準型(二段式)】時段電價說明：';
      content = '📅 夏月 (6/1 ~ 9/30)\n'
                '• 週一～週五：\n   - 00:00~09:00 離峰時段：電價 2.27 元/kWh\n   - 09:00~24:00 尖峰時段：電價 5.54 元/kWh\n'
                '• 週六：\n   - 00:00~09:00 離峰時段：電價 2.27 元/kWh\n   - 09:00~24:00 半尖峰時段：電價 2.76 元/kWh\n'
                '• 週日：\n   - 00:00~24:00 離峰時段：電價 2.27 元/kWh\n\n'
                '❄️ 非夏月 (夏月以外時間)\n'
                '• 週一～週五：\n   - 00:00~06:00、11:00~14:00 離峰時段：電價 2.15 元/kWh\n   - 06:00~11:00、14:00~24:00 尖峰時段：電價 5.39 元/kWh\n'
                '• 週六：\n   - 00:00~06:00、11:00~14:00 離峰時段：電價 2.15 元/kWh\n   - 06:00~11:00、14:00~24:00 半尖峰時段：電價 2.65 元/kWh\n'
                '• 週日：\n   - 00:00~24:00 離峰時段：電價 2.15 元/kWh';
    } else if (option == '標準型(三段式)') {
      title = '【標準型(三段式)】時段電價說明：';
      content = '📅 夏月 (6/1 ~ 9/30)\n'
                '• 週一～週五：\n   - 00:00~09:00 離峰時段：電價 2.23 元/kWh\n   - 09:00~16:00 半尖峰時段：電價 5.02 元/kWh\n   - 16:00~24:00 尖峰時段：電價 8.12 元/kWh\n'
                '• 週六：\n   - 00:00~09:00 離峰時段：電價 2.23 元/kWh\n   - 09:00~24:00 半尖峰時段：電價 2.50 元/kWh\n'
                '• 週日：\n   - 00:00~24:00 離峰時段：電價 2.23 元/kWh\n\n'
                '❄️ 非夏月 (夏月以外時間)\n'
                '• 週一～週五：\n   - 00:00~06:00、11:00~14:00 離峰時段：電價 2.12 元/kWh\n   - 06:00~11:00、14:00~24:00 半尖峰時段：電價 4.86 元/kWh\n'
                '• 週六：\n   - 00:00~06:00、11:00~14:00 離峰時段：電價 2.12 元/kWh\n   - 06:00~11:00、14:00~24:00 半尖峰時段：電價 2.40 元/kWh\n'
                '• 週日：\n   - 00:00~24:00 離峰時段：電價 2.12 元/kWh';
    } else {
      title = '【一般累進表燈(住商)】說明：';
      content = '依台電非時間電價之非營業用/營業用累進段數計費，無固定尖離峰時段區分。';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal)),
          const SizedBox(height: 10),
          Text(content, style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: AppBar(
        title: const Text('電價方案', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))]
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('請選擇您的台電電價方案：', style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),

                        DropdownButtonFormField<String>(
                          initialValue: _selectedTariff,
                          decoration: InputDecoration(
                            labelText: '電價方案',
                            labelStyle: const TextStyle(color: Colors.teal),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            prefixIcon: const Icon(Icons.price_change_outlined, color: Colors.teal),
                          ),
                          items: _tariffOptions.map((option) => DropdownMenuItem<String>(value: option, child: Text(option, style: const TextStyle(fontSize: 14)))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedTariff = val);
                          },
                        ),

                        if (_selectedTariff == '一般累進表燈(住商)') ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: _rateController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: '當期每度平均單價 (元/度)',
                              hintText: '請輸入電費單的「當期每度平均單價」',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: const Color(0xFFF5F5F5),
                              prefixIcon: const Icon(Icons.attach_money, color: Colors.teal),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 12.0),
                            child: Text('※ 備註：可依據您近期電費單上的「當期每度平均單價」填寫，以利系統為您估算發電效益，預設值為3.5元/度。', style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.4)),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  _buildTariffDetailNotice(_selectedTariff),
                  const SizedBox(height: 32),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isSaving 
                        ? null 
                        : (widget.isRootOrOwner 
                            ? _saveTariffToSupabase 
                            : () {
                                ScaffoldMessenger.of(context).clearSnackBars(); 
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('權限不足，無法執行此功能'),
                                  backgroundColor: Colors.orange
                                ));
                              }),
                    child: Text(_isSaving ? '儲存中...' : '儲存設定', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ],
              ),
            ),
    );
  }
}

// ==========================================
// 4. 惡劣天氣預測設定
// ==========================================
class WeatherForecastScreen extends StatefulWidget {
  final String deviceDbId;
  final bool isRootOrOwner; 
  const WeatherForecastScreen({super.key, required this.deviceDbId, required this.isRootOrOwner});

  @override
  State<WeatherForecastScreen> createState() => _WeatherForecastScreenState();
}

class _WeatherForecastScreenState extends State<WeatherForecastScreen> {
  bool _isLoadingWeather = true;
  String _currentAddress = '讀取中...';
  List<Map<String, String>> _forecastList = [];
  bool _isStormBackupMode = false; 

  @override
  void initState() {
    super.initState();
    _fetchAddressAnd3HourForecast();
  }

  Future<void> _updateBackupProtectionToggle(bool enabled) async {
    setState(() {
      GlobalState.isBackupProtectionEnabled = enabled;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('backup_protection_enabled', enabled);

      if (user != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({'backup_protection_enabled': enabled})
            .eq('id', user.id);
      }
      
      // 🎯 紀錄: 惡劣天氣預測切換
      await logUserAction('更改天氣備援預測', details: '將預測提醒改為: ${enabled ? "開啟" : "關閉"}');

    } catch (e) {
      debugPrint('更新備援開關狀態失敗: $e'); 
    }
  }

  Future<void> _enableStormBackupMode() async {
    if (widget.deviceDbId.isEmpty) return;

    try {
      final data = await Supabase.instance.client
          .from('devices')
          .select('sn')
          .eq('id', widget.deviceDbId)
          .single();
      final String sn = data['sn'];

      List<String> commandsToDeploy = [
        '^S011DST0,06,09\r',
        '^S019TOU0,0,1,0000,0000\r',
        '^S019TOU0,1,1,0000,0000\r'
      ];

      final response = await Supabase.instance.client.functions.invoke(
        'send-device-command',
        body: {
          'sn': sn,
          'commands': commandsToDeploy, 
        },
      );

      if (response.status != 200) {
        throw Exception('雲端派發給設備失敗');
      }

      await Supabase.instance.client
          .from('devices')
          .update({'is_storm_backup_mode': true})
          .eq('id', widget.deviceDbId);

      // 🎯 紀錄: 啟動惡劣天氣備援模式
      await logUserAction('開啟備援模式', details: '針對設備 $sn 啟動惡劣天氣備援模式');

      if (mounted) {
        setState(() {
          _isStormBackupMode = true;
        });

        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已開啟「惡劣天氣備援模式」'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_getFriendlyErrorMsg(e)),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Future<void> _fetchAddressAnd3HourForecast() async {
    setState(() { _isLoadingWeather = true; });

    try {
      if (widget.deviceDbId.isEmpty) {
        setState(() {
          _currentAddress = '未選擇設備';
          _isLoadingWeather = false;
        });
        return;
      }

      final data = await Supabase.instance.client
          .from('devices')
          .select('address, is_storm_backup_mode') 
          .eq('id', widget.deviceDbId)
          .single();

      final String rawAddr = (data['address'] ?? '').toString().trim();
      
      _isStormBackupMode = data['is_storm_backup_mode'] ?? false;

      if (rawAddr.isEmpty || rawAddr == '尚未設定' || rawAddr == '未設定安裝區域') {
        setState(() {
          _currentAddress = '尚未設定安裝區域';
          _isLoadingWeather = false;
        });
        return;
      }

      _currentAddress = rawAddr;

      String city = rawAddr;
      if (rawAddr.length >= 3) {
        city = rawAddr.substring(0, 3);
      }
      String cwaCityName = city.replaceAll('台', '臺');

      final url = 'https://opendata.cwa.gov.tw/api/v1/rest/datastore/F-C0032-001?Authorization=$cwaApiKey&locationName=$cwaCityName';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final jsonResult = jsonDecode(response.body);
        final locationList = jsonResult['records']['location'] as List;

        if (locationList.isNotEmpty) {
          final weatherElements = locationList.first['weatherElement'] as List;

          List timeSeriesWx = [];
          List timeSeriesPoP = [];
          List timeSeriesMinT = [];
          List timeSeriesMaxT = [];

          for (var element in weatherElements) {
            String elementName = element['elementName'];
            if (elementName == 'Wx') timeSeriesWx = element['time'];
            if (elementName == 'PoP') timeSeriesPoP = element['time'];
            if (elementName == 'MinT') timeSeriesMinT = element['time'];
            if (elementName == 'MaxT') timeSeriesMaxT = element['time'];
          }

          List<Map<String, String>> tempList = [];
          DateTime now = DateTime.now();

          for (int i = 0; i < 24; i++) {
            DateTime targetTime = now.add(Duration(hours: i));
            String hourLabel = '${targetTime.hour.toString().padLeft(2, '0')}:00';
            
            String wx = '晴時多雲';
            String pop = '0';
            String minT = '25';
            String maxT = '30';

            for (int j = 0; j < timeSeriesWx.length; j++) {
              DateTime apiStartTime = DateTime.parse(timeSeriesWx[j]['startTime']);
              DateTime apiEndTime = DateTime.parse(timeSeriesWx[j]['endTime']);

              if (targetTime.isAfter(apiStartTime.subtract(const Duration(seconds: 1))) && 
                  targetTime.isBefore(apiEndTime)) {
                
                wx = timeSeriesWx[j]['parameter']['parameterName'] ?? '';
                pop = (j < timeSeriesPoP.length) ? (timeSeriesPoP[j]['parameter']['parameterName'] ?? '0') : '0';
                minT = (j < timeSeriesMinT.length) ? (timeSeriesMinT[j]['parameter']['parameterName'] ?? '25') : '25';
                maxT = (j < timeSeriesMaxT.length) ? (timeSeriesMaxT[j]['parameter']['parameterName'] ?? '30') : '30';
                break; 
              }
            }

            tempList.add({
              'time': hourLabel,
              'wx': wx,
              'pop': '$pop%',
              'temp': '$minT~$maxT°C',
            });
          }

          if (mounted) {
            setState(() {
              _forecastList = tempList;
              _isLoadingWeather = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isLoadingWeather = false; });
      }
    }
  }

  IconData _getWeatherIcon(String wx) {
    if (wx.contains('雷')) return Icons.thunderstorm_rounded;
    if (wx.contains('雨')) return Icons.umbrella_rounded;
    if (wx.contains('雲') || wx.contains('陰')) return Icons.cloud_rounded;
    return Icons.wb_sunny_rounded;
  }

  Color _getWeatherIconColor(String wx) {
    if (wx.contains('雷')) return Colors.purpleAccent.shade100;
    if (wx.contains('雨')) return Colors.blueAccent;
    if (wx.contains('雲') || wx.contains('陰')) return Colors.blueGrey;
    return Colors.amber;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      extendBody: true, 
      backgroundColor: Colors.transparent, 
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/weather_full_bg.png', 
                fit: BoxFit.cover,
              ),
            ),
            
            SafeArea(
              bottom: false, 
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 160),

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
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: const Text('惡劣天氣預測提醒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal)),
                                subtitle: Text(GlobalState.isBackupProtectionEnabled ? '已開啟' : '已關閉', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                activeThumbColor: Colors.white,
                                activeTrackColor: Colors.teal,
                                value: GlobalState.isBackupProtectionEnabled,
                                onChanged: (bool val) => _updateBackupProtectionToggle(val),
                              ),
                              
                              const SizedBox(height: 4), 
                              
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                                child: const Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.gpp_good_rounded, color: Colors.orange, size: 18),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '當您啟用「惡劣天氣備援模式」，系統將暫停您的時間電價(TOU)排程，並盡可能將電池維持在高儲備量狀態',
                                        style: TextStyle(fontSize: 11, color: Colors.black87, height: 1.4, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 16),
                              
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isStormBackupMode ? Colors.grey : Colors.red.shade600,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: _isStormBackupMode ? 0 : 2,
                                  ),
                                  onPressed: _isStormBackupMode 
                                      ? null 
                                      : (widget.isRootOrOwner 
                                          ? _enableStormBackupMode 
                                          : () {
                                              ScaffoldMessenger.of(context).clearSnackBars(); 
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                                content: Text('權限不足，無法執行此功能'),
                                                backgroundColor: Colors.orange
                                              ));
                                            }),
                                  child: Text(
                                    _isStormBackupMode ? '已開啟「惡劣天氣備援模式」' : '開啟「惡劣天氣備援模式」', 
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

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
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('📍 未來24小時天氣預測', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal)),
                                  IconButton(
                                    icon: const Icon(Icons.refresh, color: Colors.teal, size: 20),
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                    onPressed: _fetchAddressAnd3HourForecast,
                                  )
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('設備安裝區域：$_currentAddress', style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12), 

                              _isLoadingWeather
                                  ? const Center(child: Padding(padding: EdgeInsets.all(20.0), child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal))))
                                  : _forecastList.isEmpty
                                      ? Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
                                          child: const Text('「尚未設定安裝區域」或「無法取得當前區域預報」', style: TextStyle(color: Colors.black54, fontSize: 13), textAlign: TextAlign.center),
                                        )
                                      : SizedBox(
                                          height: 90, 
                                          child: ListView.builder(
                                            scrollDirection: Axis.horizontal, 
                                            itemCount: _forecastList.length,
                                            itemBuilder: (context, index) {
                                              final item = _forecastList[index];
                                              final String wx = item['wx'] ?? '';

                                              return Container(
                                                width: 76, 
                                                margin: const EdgeInsets.only(right: 8),
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(item['time'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                                                    const SizedBox(height: 8), 
                                                    Icon(_getWeatherIcon(wx), color: _getWeatherIconColor(wx), size: 30), 
                                                    const SizedBox(height: 8), 
                                                    Text(item['temp'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 13)),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ),
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