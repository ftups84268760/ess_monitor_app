import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 🎯 定義 TOU 時段的資料結構，並加入 JSON 轉換能力
class TouPeriod {
  final int a; // 0: 非夏月/全年, 1: 夏月
  final int b; // 0: 第一組, 1: 第二組
  int state;   // 0: 關閉, 1: 充電, 2: 放電
  TimeOfDay startTime;
  TimeOfDay endTime;

  TouPeriod({
    required this.a,
    required this.b,
    this.state = 0,
    this.startTime = const TimeOfDay(hour: 0, minute: 0),
    this.endTime = const TimeOfDay(hour: 0, minute: 0),
  });

  // 轉換為硬體指令格式
  String toCommandString() {
    final start = '${startTime.hour.toString().padLeft(2, '0')}${startTime.minute.toString().padLeft(2, '0')}';
    final end = '${endTime.hour.toString().padLeft(2, '0')}${endTime.minute.toString().padLeft(2, '0')}';
    return '^S019TOU$a,$b,$state,$start,$end\r';
  }

  // 轉換為 JSON 以便存入資料庫
  Map<String, dynamic> toJson() {
    return {
      'state': state,
      'start': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
      'end': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
    };
  }

  // 從資料庫 JSON 讀取設定
  void loadFromJson(Map<String, dynamic>? json) {
    if (json == null) return;
    if (json['state'] != null) state = json['state'];
    if (json['start'] != null) {
      final parts = json['start'].split(':');
      if (parts.length == 2) startTime = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
    }
    if (json['end'] != null) {
      final parts = json['end'].split(':');
      if (parts.length == 2) endTime = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
    }
  }
}

class TouSettingsScreen extends StatefulWidget {
  final String deviceDbId;
  final bool isRootOrOwner; // 🎯 接收權限參數

  const TouSettingsScreen({
    super.key, 
    required this.deviceDbId, 
    required this.isRootOrOwner
  });

  @override
  State<TouSettingsScreen> createState() => _TouSettingsScreenState();
}

class _TouSettingsScreenState extends State<TouSettingsScreen> {
  bool _isLoading = true;            
  bool _isSending = false;           

  // 季節模式與月份設定
  bool _isSeasonModeEnabled = false; 
  int _summerStartMonth = 6;         
  int _summerEndMonth = 9;           

  // 預先實例化 4 組設定
  final TouPeriod _summerSlot0 = TouPeriod(a: 1, b: 0);
  final TouPeriod _summerSlot1 = TouPeriod(a: 1, b: 1);
  final TouPeriod _winterSlot0 = TouPeriod(a: 0, b: 0);
  final TouPeriod _winterSlot1 = TouPeriod(a: 0, b: 1);

  @override
  void initState() {
    super.initState();
    _fetchTouSettings(); 
  }

  // 🎯 從 Supabase 讀取現有設定
  Future<void> _fetchTouSettings() async {
    try {
      if (widget.deviceDbId.isEmpty) return;

      final data = await Supabase.instance.client
          .from('devices')
          .select('tou_settings')
          .eq('id', widget.deviceDbId)
          .single();

      final settings = data['tou_settings'];
      if (settings != null && settings is Map<String, dynamic>) {
        setState(() {
          _isSeasonModeEnabled = settings['isSeasonModeEnabled'] ?? false;
          _summerStartMonth = settings['summerStartMonth'] ?? 6;
          _summerEndMonth = settings['summerEndMonth'] ?? 9;
          
          _summerSlot0.loadFromJson(settings['summerSlot0']);
          _summerSlot1.loadFromJson(settings['summerSlot1']);
          _winterSlot0.loadFromJson(settings['winterSlot0']);
          _winterSlot1.loadFromJson(settings['winterSlot1']);
        });
      }
    } catch (e) {
      debugPrint('讀取 TOU 設定失敗: $e');
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  // 動態回傳運行狀態說明
  String _getStateDescription(int state) {
    switch (state) {
      case 0:
        return '此組時間段不生效，若時段1和時段2都選擇關閉(Disable)，電池只能通過太陽能進行充電，且電池無法放電';
      case 1:
        return '此組時間段內，由「市電」+「太陽能」給電池充電';
      case 2:
        return '此組時間段內，由「電池」+「太陽能」給負載供電';
      default:
        return '';
    }
  }

  // 呼叫系統原生的時間選擇器
  Future<void> _selectTime(BuildContext context, TouPeriod period, bool isStart) async {
    final TimeOfDay initialTime = isStart ? period.startTime : period.endTime;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      initialEntryMode: TimePickerEntryMode.inputOnly, 
      helpText: '時間範圍：00:00~23:59',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          period.startTime = picked;
        } else {
          period.endTime = picked;
        }
      });
    }
  }

  // 🎯 執行批次發送並將設定存入 Supabase
  Future<void> _sendBatchCommands() async {
    if (widget.deviceDbId.isEmpty) return;
    
    setState(() { _isSending = true; });

    List<String> commandsToDeploy = [];

    // 1. 組裝 ^S011DST 指令
    final int dstState = _isSeasonModeEnabled ? 1 : 0;
    final String bb = _summerStartMonth.toString().padLeft(2, '0');
    final String cc = _summerEndMonth.toString().padLeft(2, '0');
    commandsToDeploy.add('^S011DST$dstState,$bb,$cc\r');

    // 2. 組裝 ^S019TOU 指令群
    if (_isSeasonModeEnabled) {
      commandsToDeploy.add(_summerSlot0.toCommandString());
      commandsToDeploy.add(_summerSlot1.toCommandString());
      commandsToDeploy.add(_winterSlot0.toCommandString());
      commandsToDeploy.add(_winterSlot1.toCommandString());
    } else {
      commandsToDeploy.add(_winterSlot0.toCommandString());
      commandsToDeploy.add(_winterSlot1.toCommandString());
    }

    try {
      // 3. 準備寫入資料庫的 JSON 結構
      final Map<String, dynamic> newTouSettingsJson = {
        'isSeasonModeEnabled': _isSeasonModeEnabled,
        'summerStartMonth': _summerStartMonth,
        'summerEndMonth': _summerEndMonth,
        'summerSlot0': _summerSlot0.toJson(),
        'summerSlot1': _summerSlot1.toJson(),
        'winterSlot0': _winterSlot0.toJson(),
        'winterSlot1': _winterSlot1.toJson(),
      };

      // 取得設備 SN 並同時更新雲端設定
      final data = await Supabase.instance.client
          .from('devices')
          .update({'tou_settings': newTouSettingsJson}) 
          .eq('id', widget.deviceDbId)
          .select('sn')
          .single();

      final String sn = data['sn'];

      // 呼叫 Edge Function 發送實體指令
      final response = await Supabase.instance.client.functions.invoke(
        'send-device-command',
        body: {
          'sn': sn,
          'commands': commandsToDeploy, 
        },
      );

      if (response.status == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('共 ${commandsToDeploy.length} 條設定已成功同步至設備與雲端！'),
              backgroundColor: Colors.teal,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        throw Exception('雲端派發給設備失敗');
      }
    } catch (e) {
      debugPrint('設定同步錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('設定同步失敗，請檢查網路連線。'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() { _isSending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('時間電價(TOU)排程設定', style: TextStyle(color: Colors.black87, fontSize: 17, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.teal))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 8),
                child: Text('季節模式', style: TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeThumbColor: Colors.white,
                      activeTrackColor: Colors.teal,
                      title: const Text('夏月/非夏月', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: const Text('開啟後可設定夏月區段，其餘則為非夏月區段', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      value: _isSeasonModeEnabled,
                      onChanged: (bool value) => setState(() => _isSeasonModeEnabled = value),
                    ),
                    if (_isSeasonModeEnabled) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            const Text('夏月區間：', style: TextStyle(fontSize: 14)),
                            const Spacer(),
                            _buildMonthDropdown(_summerStartMonth, (val) => setState(() => _summerStartMonth = val!)),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('至')),
                            _buildMonthDropdown(_summerEndMonth, (val) => setState(() => _summerEndMonth = val!)),
                          ],
                        ),
                      ),
                    ]
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              if (_isSeasonModeEnabled) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Text('夏月排程 ($_summerStartMonth月~$_summerEndMonth月)', style: const TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                _buildSlotCard('夏月 (時段 1)', _summerSlot0),
                _buildSlotCard('夏月 (時段 2)', _summerSlot1),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.only(left: 8, bottom: 8),
                  child: Text('非夏月排程', style: TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                _buildSlotCard('非夏月 (時段 1)', _winterSlot0),
                _buildSlotCard('非夏月 (時段 2)', _winterSlot1),
              ] else ...[
                const Padding(
                  padding: EdgeInsets.only(left: 8, bottom: 8),
                  child: Text('全年排程', style: TextStyle(color: Colors.teal, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                _buildSlotCard('全年 (時段 1)', _winterSlot0),
                _buildSlotCard('全年 (時段 2)', _winterSlot1),
              ],

              const SizedBox(height: 32),
              ElevatedButton(
                // 🎯 核心攔截：統一警告提示風格
                onPressed: _isSending 
                    ? null 
                    : (widget.isRootOrOwner 
                        ? _sendBatchCommands 
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('權限不足：僅擁有者或系統管理員(root)可執行此功能。'),
                              backgroundColor: Colors.orange
                            ));
                          }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _isSending ? '儲存與同步中...' : '儲存設定', 
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
    );
  }

  // 輔助 UI 元件：月份選擇器
  Widget _buildMonthDropdown(int currentValue, Function(int?) onChanged) {
    return DropdownButton<int>(
      value: currentValue,
      underline: Container(height: 2, color: Colors.teal),
      items: List.generate(12, (index) {
        int month = index + 1;
        return DropdownMenuItem(value: month, child: Text('$month月'));
      }),
      onChanged: onChanged,
    );
  }

  // 輔助 UI 元件：時段設定卡片
  Widget _buildSlotCard(String title, TouPeriod period) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        subtitle: Text(
          '狀態: ${period.state == 0 ? '關閉' : period.state == 1 ? '充電' : '放電'} | ${period.startTime.format(context)} - ${period.endTime.format(context)}',
          style: TextStyle(fontSize: 12, color: period.state == 0 ? Colors.black38 : Colors.teal),
        ),
        children: [
          const Divider(height: 1),
          ListTile(
            title: const Text('運行狀態(State)', style: TextStyle(fontSize: 14)),
            trailing: DropdownButton<int>(
              value: period.state,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('0: 關閉 (Disable)')),
                DropdownMenuItem(value: 1, child: Text('1: 充電 (Charge)')),
                DropdownMenuItem(value: 2, child: Text('2: 放電 (Discharge)')),
              ],
              onChanged: (int? value) {
                if (value != null) setState(() => period.state = value);
              },
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: period.state == 0 ? Colors.grey.withValues(alpha: 0.1) : Colors.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline, 
                    size: 18, 
                    color: period.state == 0 ? Colors.black45 : Colors.teal
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getStateDescription(period.state),
                      style: TextStyle(
                        fontSize: 12, 
                        color: period.state == 0 ? Colors.black54 : Colors.teal.shade800, 
                        height: 1.4
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.play_circle_outline, color: Colors.teal),
            title: const Text('開始時間', style: TextStyle(fontSize: 14)),
            subtitle: const Text('輸入時間範圍為：00:00~23:59', style: TextStyle(fontSize: 11, color: Colors.black45)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
              child: Text(period.startTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            onTap: () => _selectTime(context, period, true),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.stop_circle_outlined, color: Colors.orange),
            title: const Text('結束時間', style: TextStyle(fontSize: 14)),
            subtitle: const Text('輸入時間範圍為：00:00~23:59', style: TextStyle(fontSize: 11, color: Colors.black45)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
              child: Text(period.endTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            onTap: () => _selectTime(context, period, false),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}