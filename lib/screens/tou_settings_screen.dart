import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';

class TouPeriod {
  final int a; 
  final int b; 
  int state;   
  TimeOfDay startTime;
  TimeOfDay endTime;

  TouPeriod({
    required this.a,
    required this.b,
    this.state = 0,
    this.startTime = const TimeOfDay(hour: 0, minute: 0),
    this.endTime = const TimeOfDay(hour: 0, minute: 0),
  });

  String toCommandString() {
    final start = '${startTime.hour.toString().padLeft(2, '0')}${startTime.minute.toString().padLeft(2, '0')}';
    final end = '${endTime.hour.toString().padLeft(2, '0')}${endTime.minute.toString().padLeft(2, '0')}';
    return '^S019TOU$a,$b,$state,$start,$end\r';
  }

  Map<String, dynamic> toJson() {
    return {
      'state': state,
      'start': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
      'end': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
    };
  }

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
  final bool isRootOrOwner; 

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

  bool _isSeasonModeEnabled = false; 
  int _summerStartMonth = 6;         
  int _summerEndMonth = 9;           

  final TouPeriod _summerSlot0 = TouPeriod(a: 1, b: 0);
  final TouPeriod _summerSlot1 = TouPeriod(a: 1, b: 1);
  final TouPeriod _winterSlot0 = TouPeriod(a: 0, b: 0);
  final TouPeriod _winterSlot1 = TouPeriod(a: 0, b: 1);

  @override
  void initState() {
    super.initState();
    _fetchTouSettings(); 
  }

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

  Future<void> _selectTime(BuildContext context, TouPeriod period, bool isStart) async {
    final TimeOfDay initialTime = isStart ? period.startTime : period.endTime;
    DateTime tempTime = DateTime(2020, 1, 1, initialTime.hour, initialTime.minute);

    await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext builderContext) {
        return Container(
          height: 260,
          color: Colors.white,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: const Text('取消', style: TextStyle(color: Colors.grey)),
                    onPressed: () => Navigator.of(builderContext).pop(),
                  ),
                  CupertinoButton(
                    child: const Text('確定', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      if (mounted) {
                        setState(() {
                          if (isStart) {
                            period.startTime = TimeOfDay(hour: tempTime.hour, minute: tempTime.minute);
                          } else {
                            period.endTime = TimeOfDay(hour: tempTime.hour, minute: tempTime.minute);
                          }
                        });
                      }
                      Navigator.of(builderContext).pop();
                    },
                  ),
                ],
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true,
                    initialDateTime: tempTime,
                    onDateTimeChanged: (DateTime newTime) {
                      tempTime = newTime;
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendBatchCommands() async {
    if (widget.deviceDbId.isEmpty) return;
    
    setState(() { _isSending = true; });

    List<String> commandsToDeploy = [];

    final int dstState = _isSeasonModeEnabled ? 1 : 0;
    final String bb = _summerStartMonth.toString().padLeft(2, '0');
    final String cc = _summerEndMonth.toString().padLeft(2, '0');
    commandsToDeploy.add('^S011DST$dstState,$bb,$cc\r');

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
      final Map<String, dynamic> newTouSettingsJson = {
        'isSeasonModeEnabled': _isSeasonModeEnabled,
        'summerStartMonth': _summerStartMonth,
        'summerEndMonth': _summerEndMonth,
        'summerSlot0': _summerSlot0.toJson(),
        'summerSlot1': _summerSlot1.toJson(),
        'winterSlot0': _winterSlot0.toJson(),
        'winterSlot1': _winterSlot1.toJson(),
      };

      final data = await Supabase.instance.client
          .from('devices')
          .update({'tou_settings': newTouSettingsJson}) 
          .eq('id', widget.deviceDbId)
          .select('sn')
          .single();

      final String sn = data['sn'];

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
              content: Text('已成功設定時間電價排程(共 ${commandsToDeploy.length} 組設定)'),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('時間電價(TOU)排程', style: TextStyle(color: Colors.black87, fontSize: 17, fontWeight: FontWeight.bold)),
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
              // 🎯 替換：移除邊線改為柔和陰影
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
                    SwitchListTile(
                      activeThumbColor: Colors.white,
                      activeTrackColor: Colors.teal,
                      title: const Text('夏月/非夏月', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: const Text('開啟後可設定夏月區段，其餘則為非夏月區段', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      value: _isSeasonModeEnabled,
                      onChanged: (bool value) => setState(() => _isSeasonModeEnabled = value),
                    ),
                    if (_isSeasonModeEnabled) ...[
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
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

              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isSending 
                    ? null 
                    : (widget.isRootOrOwner 
                        ? _sendBatchCommands 
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('權限不足，無法執行此功能'),
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

  // 🎯 替換：改為立體無框卡片設計
  Widget _buildSlotCard(String title, TouPeriod period) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))
        ]
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          subtitle: Text(
            '狀態: ${period.state == 0 ? '關閉' : period.state == 1 ? '充電' : '放電'} | ${period.startTime.format(context)} - ${period.endTime.format(context)}',
            style: TextStyle(fontSize: 12, color: period.state == 0 ? Colors.black38 : Colors.teal),
          ),
          children: [
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
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
                  color: period.state == 0 ? Colors.grey.shade50 : Colors.teal.withValues(alpha: 0.05),
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
            
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            ListTile(
              leading: const Icon(Icons.play_circle_outline, color: Colors.teal),
              title: const Text('開始時間', style: TextStyle(fontSize: 14)),
              subtitle: const Text('點擊右側時間來進行設定', style: TextStyle(fontSize: 11, color: Colors.black45)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
                child: Text(period.startTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              onTap: () => _selectTime(context, period, true),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            ListTile(
              leading: const Icon(Icons.stop_circle_outlined, color: Colors.orange),
              title: const Text('結束時間', style: TextStyle(fontSize: 14)),
              subtitle: const Text('點擊右側時間來進行設定', style: TextStyle(fontSize: 11, color: Colors.black45)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
                child: Text(period.endTime.format(context), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              onTap: () => _selectTime(context, period, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}