import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import 'tou_settings_screen.dart';
import 'dashboard/dtu_replacement_screen.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

// 🎯 更新為 StatefulWidget 進行權限管理
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
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text('系統設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSubMenuTile(context, Icons.tsunami_outlined, '惡劣天氣預測', WeatherForecastScreen(deviceDbId: widget.deviceDbId, isRootOrOwner: _isRootOrOwner)),
                _buildSubMenuTile(context, Icons.schedule, '時間電價(TOU)排程', TouSettingsScreen(deviceDbId: widget.deviceDbId, isRootOrOwner: _isRootOrOwner)),
                _buildSubMenuTile(context, Icons.hourglass_bottom_rounded, '電價方案', ElectricityTariffScreen(deviceDbId: widget.deviceDbId, isRootOrOwner: _isRootOrOwner)),
                _buildSubMenuTile(context, Icons.developer_board, '設備資訊', DeviceInfoSettingsScreen(deviceDbId: widget.deviceDbId, isRootOrOwner: _isRootOrOwner)),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Colors.black12, height: 1),
                ),
                _buildSubMenuTile(
                  context, 
                  Icons.tune_rounded, 
                  '進階設定', 
                  DeviceAdvancedSettingsScreen(deviceDbId: widget.deviceDbId, inverterSn: widget.inverterSn ?? '', isRootOrOwner: _isRootOrOwner)
                ),
              ],
            ),
    );
  }

  Widget _buildSubMenuTile(BuildContext context, IconData icon, String title, Widget? targetScreen) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: Colors.teal),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black26),
        onTap: () {
          if (!_hasPermission) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('無此修改權限，僅設備擁有者可進入設定。'),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 2),
            ));
            return;
          }

          if (targetScreen != null) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => targetScreen));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「$title」功能模組已就緒，正等待通訊協議對齊。')));
          }
        },
      ),
    );
  }
}

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
      debugPrint('全域推播狀態儲存失敗');
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
      // 靜默處理預設值
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('推播通知條件已成功儲存！'),
          backgroundColor: Colors.teal,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('儲存失敗，請檢查網路連線或 Supabase 權限。'),
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
      backgroundColor: const Color(0xFFF8FAFC),
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
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: SwitchListTile(
                    secondary: const Icon(Icons.notifications_active, color: Colors.teal),
                    title: const Text('允許所有系統推播通知', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                    subtitle: const Text('關閉後將暫停接收所有來自 APP 的警告與提示', style: TextStyle(fontSize: 11, color: Colors.black45)),
                    activeThumbColor: Colors.white,
                    activeTrackColor: Colors.teal,
                    value: isMasterEnabled,
                    onChanged: (bool value) => _updateMasterToggle(value),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                const Padding(
                  padding: EdgeInsets.only(left: 4.0, bottom: 8.0),
                  child: Text('細項條件設定 (需開啟總開關)：', style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
                ),

                Opacity(
                  opacity: isMasterEnabled ? 1.0 : 0.5,
                  child: IgnorePointer(
                    ignoring: !isMasterEnabled,
                    child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

                const SizedBox(height: 24),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isMasterEnabled ? Colors.teal : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      activeThumbColor: Colors.teal,
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black45)),
      value: value,
      onChanged: onChanged,
    );
  }
}

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
          .select('electricity_tariff')
          .eq('id', widget.deviceDbId)
          .single();

      if (mounted) {
        setState(() {
          _selectedTariff = data['electricity_tariff'] ?? '一般累進表燈(住商)';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTariffToSupabase() async {
    if (widget.deviceDbId.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      await Supabase.instance.client.from('devices').update({
        'electricity_tariff': _selectedTariff,
      }).eq('id', widget.deviceDbId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('電價方案設定成功！'),
          backgroundColor: Colors.teal,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('儲存失敗，請檢查網路連線。'),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildTariffDetailNotice(String option) {
    if (option == '簡易型(二段式)') {
      return _buildNoticeContainer(
        title: '【簡易型(二段式)】時段電價說明：',
        content:
          '📅 夏月 (6/1 ~ 9/30)\n'
          '• 週一～週五：\n'
          '   - 00:00~09:00 離峰時段：電價 2.06 元/kWh\n'
          '   - 09:00~24:00 尖峰時段：電價 5.16 元/kWh\n'
          '• 週六、週日：\n'
          '   - 00:00~24:00 離峰時段：電價 2.06 元/kWh\n\n'
          '❄️ 非夏月 (夏月以外時間)\n'
          '• 週一～週五：\n'
          '   - 00:00~06:00、11:00~14:00 離峰時段：電價 1.99 元/kWh\n'
          '   - 06:00~11:00、14:00~24:00 尖峰時段：電價 4.93 元/kWh\n'
          '• 週六、週日：\n'
          '   - 00:00~24:00 離峰時段：電價 1.99 元/kWh',
      );
    } else if (option == '簡易型(三段式)') {
      return _buildNoticeContainer(
        title: '【簡易型(三段式)】時段電價說明：',
        content:
          '📅 夏月 (6/1 ~ 9/30)\n'
          '• 週一～週五：\n'
          '   - 00:00~09:00 離峰時段：電價 2.06 元/kWh\n'
          '   - 09:00~16:00 半尖峰時段：電價 4.69 元/kWh\n'
          '   - 16:00~24:00 尖峰時段：電價 7.13 元/kWh\n'
          '• 週六、週日：\n'
          '   - 00:00~24:00 離峰時段：電價 2.06 元/kWh\n\n'
          '❄️ 非夏月 (夏月以外時間)\n'
          '• 週一～週五：\n'
          '   - 00:00~06:00、11:00~14:00 離峰時段：電價 1.99 元/kWh\n'
          '   - 06:00~11:00、14:00~24:00 半尖峰時段：電價 4.48 元/kWh\n'
          '• 週六、週日：\n'
          '   - 00:00~24:00 離峰時段：電價 1.99 元/kWh',
      );
    } else if (option == '標準型(二段式)') {
      return _buildNoticeContainer(
        title: '【標準型(二段式)】時段電價說明：',
        content:
          '📅 夏月 (6/1 ~ 9/30)\n'
          '• 週一～週五：\n'
          '   - 00:00~09:00 離峰時段：電價 2.27 元/kWh\n'
          '   - 09:00~24:00 尖峰時段：電價 5.54 元/kWh\n'
          '• 週六：\n'
          '   - 00:00~09:00 離峰時段：電價 2.27 元/kWh\n'
          '   - 09:00~24:00 半尖峰時段：電價 2.76 元/kWh\n'
          '• 週日：\n'
          '   - 00:00~24:00 離峰時段：電價 2.27 元/kWh\n\n'
          '❄️ 非夏月 (夏月以外時間)\n'
          '• 週一～週五：\n'
          '   - 00:00~06:00、11:00~14:00 離峰時段：電價 2.15 元/kWh\n'
          '   - 06:00~11:00、14:00~24:00 尖峰時段：電價 5.39 元/kWh\n'
          '• 週六：\n'
          '   - 00:00~06:00、11:00~14:00 離峰時段：電價 2.15 元/kWh\n'
          '   - 06:00~11:00、14:00~24:00 半尖峰時段：電價 2.65 元/kWh\n'
          '• 週日：\n'
          '   - 00:00~24:00 離峰時段：電價 2.15 元/kWh',
      );
    } else if (option == '標準型(三段式)') {
      return _buildNoticeContainer(
        title: '【標準型(三段式)】時段電價說明：',
        content:
          '📅 夏月 (6/1 ~ 9/30)\n'
          '• 週一～週五：\n'
          '   - 00:00~09:00 離峰時段：電價 2.23 元/kWh\n'
          '   - 09:00~16:00 半尖峰時段：電價 5.02 元/kWh\n'
          '   - 16:00~24:00 尖峰時段：電價 8.12 元/kWh\n'
          '• 週六：\n'
          '   - 00:00~09:00 離峰時段：電價 2.23 元/kWh\n'
          '   - 09:00~24:00 半尖峰時段：電價 2.50 元/kWh\n'
          '• 週日：\n'
          '   - 00:00~24:00 離峰時段：電價 2.23 元/kWh\n\n'
          '❄️ 非夏月 (夏月以外時間)\n'
          '• 週一～週五：\n'
          '   - 00:00~06:00、11:00~14:00 離峰時段：電價 2.12 元/kWh\n'
          '   - 06:00~11:00、14:00~24:00 半尖峰時段：電價 4.86 元/kWh\n'
          '• 週六：\n'
          '   - 00:00~06:00、11:00~14:00 離峰時段：電價 2.12 元/kWh\n'
          '   - 06:00~11:00、14:00~24:00 半尖峰時段：電價 2.40 元/kWh\n'
          '• 週日：\n'
          '   - 00:00~24:00 離峰時段：電價 2.12 元/kWh',
      );
    } else {
      return _buildNoticeContainer(
        title: '【一般累進表燈(住商)】說明：',
        content: '依台電非時間電價之非營業用/營業用累進段數計費，無固定尖離峰時段區分。',
      );
    }
  }

  Widget _buildNoticeContainer({required String title, required String content}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal)),
          const SizedBox(height: 8),
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
        title: const Text('電價方案設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)))
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('請選擇您的台電電價計費模式：', style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    initialValue: _selectedTariff,
                    decoration: InputDecoration(
                      labelText: '選擇電價方案',
                      labelStyle: const TextStyle(color: Colors.teal),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8), 
                        borderSide: const BorderSide(color: Colors.teal, width: 2)
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.price_change_outlined, color: Colors.teal),
                    ),
                    items: _tariffOptions.map((option) {
                      return DropdownMenuItem<String>(
                        value: option,
                        child: Text(option, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedTariff = val;
                        });
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildTariffDetailNotice(_selectedTariff),
                    ),
                  ),

                  const SizedBox(height: 12),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isSaving 
                        ? null 
                        : (widget.isRootOrOwner 
                            ? _saveTariffToSupabase 
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('權限不足：僅擁有者或系統管理員(root)可執行此功能。'),
                                  backgroundColor: Colors.orange
                                ));
                              }),
                    child: Text(_isSaving ? '儲存中...' : '儲存設定', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
    );
  }
}

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
    } catch (e) {
      // 靜默處理
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

      if (mounted) {
        setState(() {
          _isStormBackupMode = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已成功向設備發送滿充備援指令！'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('啟動備援失敗，請檢查網路連線。'),
          ),
        );
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

      if (rawAddr.isEmpty || rawAddr == '尚未設定' || rawAddr == '未設定安裝地址') {
        setState(() {
          _currentAddress = '尚未設定安裝地址';
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

            String dateSuffix = targetTime.day != now.day ? ' (明日)' : '';

            tempList.add({
              'time': '$hourLabel$dateSuffix',
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('惡劣天氣預測', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: SwitchListTile(
                title: const Text('惡劣天氣預測提醒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(GlobalState.isBackupProtectionEnabled ? '已開啟' : '已關閉'),
                activeThumbColor: Colors.teal,
                value: GlobalState.isBackupProtectionEnabled,
                onChanged: (bool val) => _updateBackupProtectionToggle(val),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.gpp_good_rounded, color: Colors.orange, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '開啟惡劣天氣預測，當偵測到未來 3~6 小時內可能出現惡劣天氣時將發送推播。',
                      style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.5, fontWeight: FontWeight.w500),
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
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: _isStormBackupMode ? 0 : 2,
                ),
                onPressed: _isStormBackupMode 
                    ? null 
                    : (widget.isRootOrOwner 
                        ? _enableStormBackupMode 
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('權限不足：僅擁有者或系統管理員(root)可執行此功能。'),
                              backgroundColor: Colors.orange
                            ));
                          }),
                child: Text(
                  _isStormBackupMode ? '「惡劣天氣備援模式」執行中' : '立即啟用「惡劣天氣備援模式」', 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
                ),
              ),
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('📍 安裝地點未來24小時預測', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.teal, size: 18),
                  onPressed: _fetchAddressAnd3HourForecast,
                )
              ],
            ),
            Text('綁定地址：$_currentAddress', style: const TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),

            _isLoadingWeather
                ? const Center(child: Padding(padding: EdgeInsets.all(20.0), child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal))))
                : _forecastList.isEmpty
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                        child: const Text('尚未設定安裝地址或無法取得當前區域預報。', style: TextStyle(color: Colors.black38, fontSize: 12), textAlign: TextAlign.center),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _forecastList.length,
                        itemBuilder: (context, index) {
                          final item = _forecastList[index];
                          final String wx = item['wx'] ?? '';

                          return Card(
                            elevation: 1,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            child: ListTile(
                              dense: true,
                              leading: Icon(_getWeatherIcon(wx), color: _getWeatherIconColor(wx), size: 24),
                              title: Text('${item['time']} 起 - $wx', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                              subtitle: Text('降雨機率: ${item['pop']}', style: const TextStyle(color: Colors.blueAccent, fontSize: 11)),
                              trailing: Text(item['temp'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 12)),
                            ),
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }
}

class DeviceInfoSettingsScreen extends StatefulWidget {
  final String deviceDbId;
  final bool isRootOrOwner; 
  const DeviceInfoSettingsScreen({super.key, required this.deviceDbId, required this.isRootOrOwner});

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
    '苗栗縣': ['苗栗市', '頭份市', '竹南鎮', '苑裡鎮', '通霄鎮', '後龍鎮', '卓蘭鎮', '大湖鄉', '公館鄉', '銅鑼鄉', '南庄鄉', '頭屋鄉', '三義鄉', '西湖鄉', '造橋鄉', '三灣鄉', '狮潭鄉', '泰安鄉'],
    '台中市': ['中區', '東區', '南區', '西區', '北區', '北屯區', '西屯區', '南屯區', '太平區', '大里區', '霧峰區', '烏日區', '豐原區', '后里區', '石岡區', '東勢區', '和平區', '新社區', '潭子區', '大雅區', '神岡區', '大肚區', '沙鹿區', '龍井區', '梧棲區', '清水區', '大甲區', '外埔區', '大安區'],
    '彰化縣': ['彰化市', '員林市', '鹿港鎮', '和美鎮', '北斗鎮', '溪湖鎮', '田中鎮', '二林鎮', '線西鄉', '伸港鄉', '福興鄉', '秀水鄉', '花壇鄉', '芬園鄉', '大村鄉', '埔鹽鄉', '埔心鄉', '永靖鄉', '社頭鄉', '二水鄉', '田尾鄉', '埤頭鄉', '芳苑鄉', '大城鄉', '竹塘鄉', '溪州鄉'],
    '南投縣': ['南投市', '埔里鎮', '草屯鎮', '竹山鎮', '集集鎮', '名間鄉', '鹿谷鄉', '中寮鄉', '魚池鄉', '國姓鄉', '水里鄉', '信義鄉', '仁愛鄉'],
    '雲林縣': ['斗六市', '斗南鎮', '虎尾鎮', '西螺鎮', '土庫鎮', '北港鎮', '古坑鄉', '大埤鄉', '莿桐鄉', '林內鄉', '二崙鄉', '崙背鄉', '麥寮鄉', '東勢鄉', '褒忠鄉', '臺西鄉', '元長鄉', '四湖鄉', '口湖鄉', '水林鄉'],
    '嘉義市': ['東區', '西區'],
    '嘉義縣': ['太保市', '朴子市', '布袋鎮', '大林鎮', '民雄鄉', '溪口鄉', '新港鄉', '六腳鄉', '東石鄉', '義竹鄉', '鹿草鄉', '水上鄉', '中埔鄉', '竹崎鄉', '梅山鄉', '番路鄉', '大埔鄉', '阿里山鄉'],
    '台南市': ['中西區', '東區', '南區', '北區', '安平區', '安南區', '永康區', '歸仁區', '新化區', '左鎮區', '玉井區', '楠西區', '南化區', '仁德區', '關廟區', '龍崎區', '官田區', '麻豆區', '佳里區', '西港區', '七股區', '將軍區', '學甲區', '北門區', '新營區', '後壁區', '白河區', '東山區', '六甲區', '下營區', '柳營區', '鹽水區'],
    '高雄市': ['鹽埕區', '鼓山區', '左營區', '楠梓區', '三民區', '新興區', '前金區', '苓雅區', '前鎮區', '旗津區', '小港區', '鳳山區', '林園區', '大寮區', '大樹區', '大社區', '仁武區', '鳥松區', '岡山區', '橋頭區', '燕巢區', '田寮區', '阿蓮區', '路竹區', '湖內區', '茄萣區', '永安區', '彌陀區', '梓官區', '旗山區', '美濃區', '六龜區', '甲仙區', '杉林區', '內門區', '態源區', '那瑪夏區'],
    '屏東縣': ['屏東市', '潮州鎮', '東港鎮', '恆春鎮', '萬丹鄉', '長治鄉', '麟洛鄉', '九如鄉', '里港鄉', '鹽埔鄉', '高樹鄉', '萬巒鄉', '內埔鄉', '竹田鄉', '新埤鄉', '枋寮鄉', '新園鄉', '崁頂鄉', '林邊鄉', '南州鄉', '佳冬鄉', '琉球鄉', '車城鄉', '滿州鄉', '枋山鄉', '三地門鄉', '霧臺鄉', '瑪家鄉', '泰武鄉', '來義鄉', '春日鄉', '獅子鄉', '牡丹鄉'],
    '宜蘭縣': ['宜蘭市', '羅東鎮', '蘇澳鎮', '頭城鎮', '礁溪鄉', '壯圍鄉', '員山鄉', '冬山鄉', '五結鄉', '三星鄉', '大同鄉', '南澳鄉'],
    '花蓮縣': ['花蓮市', '鳳林鎮', '玉里鎮', '新城鄉', '吉安鄉', '壽豐鄉', '光復鄉', '豐濱鄉', '瑞穗鄉', '富里鄉', '秀林鄉', '萬榮鄉', '卓溪鄉'],
    '台東縣': ['台東市', '成功鎮', '關山鎮', '卑南鄉', '大武鄉', '太麻里鄉', '東河鄉', '長濱鄉', '鹿野鄉', '池上鄉', '綠島鄉', '延平鄉', '海端鄉', '達仁鄉', '金峰鄉', '蘭嶼鄉'],
    '澎湖縣': ['馬公市', '湖西鄉', '白沙鄉', '西嶼鄉', '望安鄉', '七美鄉'],
    '金門縣': ['金城鎮', '金湖鎮', '金沙鎮', '金寧鄉', '烈嶼鄉', '烏坵鄉'],
    '連江縣': ['南竿鄉', '北竿鄉', '莒光鄉', '東引鄉']
  };

  String? _selectedCity;
  String? _selectedDistrict;
  bool _isSaving = false;

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
          .select('sn, address, install_date')
          .eq('id', widget.deviceDbId)
          .single();

      setState(() {
        _snController.text = data['sn'] ?? '';
        _dateController.text = data['install_date'] ?? "${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}";

        String addr = data['address'] ?? '';
        for (var city in _taiwanLocations.keys) {
          if (addr.contains(city)) {
            _selectedCity = city;
            for (var dist in _taiwanLocations[city]!) {
              if (addr.contains(dist)) _selectedDistrict = dist;
            }
          }
        }
      });
    } catch (e) {
      setState(() {
        _dateController.text = "${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}";
      });
    }
  }

  Future<void> _saveDeviceSpecsToSupabase() async {
    if (widget.deviceDbId.isEmpty || _selectedCity == null || _selectedDistrict == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請選擇完整的縣市與地區！')));
      return;
    }

    setState(() { _isSaving = true; });
    try {
      String fullAddress = "$_selectedCity$_selectedDistrict";

      await Supabase.instance.client.from('devices').update({
        'address': fullAddress,
        'install_date': _dateController.text.trim(),
      }).eq('id', widget.deviceDbId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('安裝資訊已成功儲存！'),
          backgroundColor: Colors.teal
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('儲存失敗，請檢查網路連線。')));
    } finally {
      setState(() { _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('設備資訊設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _snController,
              readOnly: true,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
              decoration: const InputDecoration(
                labelText: '產品序號 (SN)',
                prefixIcon: Icon(Icons.qr_code_scanner_rounded, size: 18),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFFF5F5F5),
              ),
            ),
            const SizedBox(height: 20),

            DropdownButtonFormField<String>(
              initialValue: _selectedCity,
              hint: const Text("選擇縣市"),
              items: _taiwanLocations.keys.map((city) => DropdownMenuItem<String>(value: city, child: Text(city))).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedCity = val;
                  _selectedDistrict = null;
                });
              },
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: '縣市'),
            ),
            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              initialValue: _selectedDistrict,
              hint: const Text("選擇地區"),
              items: (_selectedCity == null ? <String>[] : _taiwanLocations[_selectedCity]!)
                  .map((dist) => DropdownMenuItem<String>(value: dist, child: Text(dist)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedDistrict = val),
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: '地區'),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _dateController,
              decoration: InputDecoration(
                labelText: '安裝日期 (YYYY/MM/DD)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_month, color: Colors.teal),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035)
                    );
                    if (picked != null) {
                      setState(() {
                        _dateController.text = "${picked.year}/${picked.month}/${picked.day}";
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 30),

            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _isSaving 
                  ? null 
                  : (widget.isRootOrOwner 
                      ? _saveDeviceSpecsToSupabase 
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('權限不足：僅擁有者或系統管理員(root)可執行此功能。'),
                            backgroundColor: Colors.orange
                          ));
                        }),
              child: Text(_isSaving ? '儲存中...' : '儲存設定', style: const TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }
}

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請輸入欲設定的帳號信箱')));
      return;
    }

    if (!makeAdmin) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('撤銷權限確認', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('確定要將 $email 降級為一般使用者嗎？\n對方將立即失去全系統設備的檢視與操作權限。'),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.teal));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('系統連線異常，請稍後再試'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('管理員權限設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.admin_panel_settings_rounded, color: Colors.redAccent, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('升級為管理員後，該帳號將獲得最高權限。若撤銷權限，該帳號將恢復為僅能檢視自己設備的一般使用者。', style: TextStyle(fontSize: 12, color: Colors.redAccent, height: 1.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('輸入欲設定的帳號 Email：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'example@email.com',
                prefixIcon: const Icon(Icons.email_outlined, color: Colors.teal),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.teal, width: 2)),
                filled: true,
                fillColor: const Color(0xFFF9F9F9),
              ),
            ),
            const SizedBox(height: 20),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal, 
                      padding: const EdgeInsets.symmetric(vertical: 14), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                    ),
                    onPressed: _isProcessing ? null : () => _changeAdminRole(true),
                    child: _isProcessing 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('指派為管理員', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: _isProcessing ? Colors.grey : Colors.redAccent)
                      )
                    ),
                    onPressed: _isProcessing ? null : () => _changeAdminRole(false),
                    child: const Text('撤銷管理員', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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

class DeviceAdvancedSettingsScreen extends StatelessWidget {
  final String deviceDbId;
  final String inverterSn;
  final bool isRootOrOwner; 

  const DeviceAdvancedSettingsScreen({
    super.key, 
    required this.deviceDbId, 
    required this.inverterSn, 
    required this.isRootOrOwner
  });

  void _promptDtuPassword(BuildContext context) {
    final TextEditingController pwdController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要密碼授權', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: pwdController,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: '請輸入通訊模組更換密碼',
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.teal)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              if (pwdController.text == 'ftups84268760') {
                Navigator.pop(context); 
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => DtuReplacementScreen(deviceDbId: deviceDbId, inverterSn: inverterSn)
                ));
              } else {
                Navigator.pop(context); 
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('授權密碼錯誤，拒絕存取！'), backgroundColor: Colors.redAccent));
              }
            },
            child: const Text('確認執行', style: TextStyle(color: Colors.teal)),
          )
        ]
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text('進階設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.battery_charging_full_rounded, color: Colors.teal),
              title: const Text('電池參數設定', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black26),
              onTap: () {
                if (!isRootOrOwner) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('權限不足：僅擁有者或系統管理員(root)可進入電池參數設定。'),
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
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.swap_horiz_rounded, color: Colors.redAccent),
              title: const Text('通訊模組(DTU)更換', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black26),
              onTap: () => _promptDtuPassword(context),
            ),
          ),
        ],
      ),
    );
  }
}

class SystemAdvancedSettingsScreen extends StatelessWidget {
  const SystemAdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text('系統進階設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.black87), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings, color: Colors.teal),
              title: const Text('管理員權限設定', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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

class BatteryParameterSettingsScreen extends StatefulWidget {
  final String deviceDbId;
  final String inverterSn;
  const BatteryParameterSettingsScreen({super.key, required this.deviceDbId, required this.inverterSn});

  @override
  State<BatteryParameterSettingsScreen> createState() => _BatteryParameterSettingsScreenState();
}

class _BatteryParameterSettingsScreenState extends State<BatteryParameterSettingsScreen> {
  bool _isLoading = false;
  MqttServerClient? _mqttClient;
  
  int _maxAcChargeCurrent = 10;  
  int _offGridDischargeSoc = 20; 
  int _offGridRecoverySoc = 30;  
  int _onGridDischargeSoc = 30;  
  int _onGridRecoverySoc = 40;   

  @override
  void initState() {
    super.initState();
    _setupDirectMqtt();
  }

  @override
  void dispose() {
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
        
        _mqttClient!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
          final recMess = c![0].payload as MqttPublishMessage;
          final payloadString = String.fromCharCodes(recMess.payload.message);
          
          if (payloadString.contains('^D092')) {
            final startIndex = payloadString.indexOf('^D092');
            final cleanString = payloadString.substring(startIndex);
            // ignore: unused_element
            _parseBatsResponse(cleanString);
          }
        });
      }
    } catch (e) {
      debugPrint('❌ MQTT 連線失敗: $e');
      _mqttClient?.disconnect();
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
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.functions.invoke(
        'send-device-command',
        body: {'sn': widget.inverterSn, 'commands': ['^P005BATS\r']},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('讀取中...'), backgroundColor: Colors.teal, duration: Duration(seconds: 2))
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('讀取失敗'), backgroundColor: Colors.redAccent));
    } finally {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isLoading) setState(() => _isLoading = false);
      });
    }
  }

  void _parseBatsResponse(String cleanString) {
    try {
      List<String> parts = cleanString.split(',');
      if (parts.length >= 22) {
        int vvvv = int.parse(parts[16]);
        int xxx = int.parse(parts[18]);
        int yyy = int.parse(parts[19]);
        int zzz = int.parse(parts[20]);
        int aaa = int.parse(RegExp(r'^\d+').firstMatch(parts[21])?.group(0) ?? '0');

        setState(() {
          _maxAcChargeCurrent = (vvvv ~/ 10).clamp(10, 100);
          _offGridDischargeSoc = xxx.clamp(0, 80);
          _offGridRecoverySoc = yyy.clamp(0, 80);
          _onGridDischargeSoc = zzz.clamp(5, 95);
          _onGridRecoverySoc = aaa.clamp(5, 100);
          _isLoading = false; 
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('參數已成功讀取'), backgroundColor: Colors.teal)
          );
        }
      }
    } catch (e) {
      debugPrint('解析失敗: $e');
    }
  }

  Future<void> _sendAcChargeCurrent() async {
    setState(() => _isLoading = true);
    try {
      String currentStr = (_maxAcChargeCurrent * 10).toString().padLeft(4, '0');
      await Supabase.instance.client.functions.invoke(
        'send-device-command',
        body: {'sn': widget.inverterSn, 'commands': ['^S011MUCHGC$currentStr\r']},
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('充電電流設定已發送'), backgroundColor: Colors.teal));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('設定失敗'), backgroundColor: Colors.redAccent));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendSocSettings() async {
    setState(() => _isLoading = true);
    try {
      String aaaStr = _offGridDischargeSoc.toString().padLeft(3, '0');
      String bbbStr = _offGridRecoverySoc.toString().padLeft(3, '0');
      String cccStr = _onGridDischargeSoc.toString().padLeft(3, '0');
      String dddStr = _onGridRecoverySoc.toString().padLeft(3, '0');
      String cmd = '^S021BATDS$aaaStr,$bbbStr,$cccStr,$dddStr\r';

      await Supabase.instance.client.functions.invoke(
        'send-device-command',
        body: {'sn': widget.inverterSn, 'commands': [cmd]},
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SOC設定已發送'), backgroundColor: Colors.teal));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('設定失敗'), backgroundColor: Colors.redAccent));
    } finally {
      setState(() => _isLoading = false);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    );
  }

  Widget _buildControlRow({
    required String title,
    required int value,
    required List<int> options,
    required String unit,
    required Function(int?) onChanged,
    Widget? trailingAction,
  }) {
    final safeValue = options.contains(value) ? value : options.first;
    
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
                    initialValue: safeValue,
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black26),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                    ),
                    items: options.map((opt) => DropdownMenuItem(value: opt, child: Text('$opt $unit', style: const TextStyle(fontSize: 15, color: Colors.black87)))).toList(),
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
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text('電池參數', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
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
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.teal, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.cloud_download_rounded, size: 20),
                  label: const Text('讀取電池設定參數', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: _queryDeviceSettings,
                ),
              ),
              const SizedBox(height: 24),

              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('充電設定', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal)),
                      const Divider(color: Colors.black12, height: 24),
                      _buildControlRow(
                        title: '最大市電充電電流',
                        value: _maxAcChargeCurrent,
                        options: _generateList(10, 100, 10),
                        unit: 'A',
                        onChanged: (v) => setState(() => _maxAcChargeCurrent = v!),
                        trailingAction: _buildSendButton(
                          label: '設定', 
                          color: Colors.green, 
                          onPressed: _sendAcChargeCurrent
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SOC相關設定', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal)),
                      const Divider(color: Colors.black12, height: 24),
                      
                      const Text('無市電(Off-Grid)狀態', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueAccent)), 
                      const SizedBox(height: 12),
                      _buildControlRow(
                        title: '電池截止放電SOC',
                        value: _offGridDischargeSoc,
                        options: _generateList(0, 80, 5),
                        unit: '%',
                        onChanged: (v) => setState(() => _offGridDischargeSoc = v!),
                      ),
                      _buildControlRow(
                        title: '電池重新放電SOC',
                        value: _offGridRecoverySoc,
                        options: _generateList(0, 80, 5),
                        unit: '%',
                        onChanged: (v) => setState(() => _offGridRecoverySoc = v!),
                      ),

                      const Padding(
                        padding: EdgeInsets.only(bottom: 16.0),
                        child: Divider(color: Colors.black12),
                      ),

                      const Text('有市電(On-Grid)狀態', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueAccent)), 
                      const SizedBox(height: 12),
                      _buildControlRow(
                        title: '電池截止放電SOC',
                        value: _onGridDischargeSoc,
                        options: _generateList(5, 95, 5),
                        unit: '%',
                        onChanged: (v) => setState(() => _onGridDischargeSoc = v!),
                      ),
                      _buildControlRow(
                        title: '電池重新放電SOC',
                        value: _onGridRecoverySoc,
                        options: _generateList(5, 100, 5),
                        unit: '%',
                        onChanged: (v) => setState(() => _onGridRecoverySoc = v!),
                      ),

                      Align(
                        alignment: Alignment.centerRight,
                        child: _buildSendButton(
                          label: '設定', 
                          color: Colors.blueAccent, 
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