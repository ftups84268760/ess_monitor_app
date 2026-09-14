import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class RawDataScreen extends StatefulWidget {
  final String deviceDbId;
  const RawDataScreen({super.key, required this.deviceDbId});

  @override
  State<RawDataScreen> createState() => _RawDataScreenState();
}

class _RawDataScreenState extends State<RawDataScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _telemetryData;
  Map<String, dynamic>? _invPsData;
  
  Timer? _liveTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;
  bool _isFetching = false; 

  @override
  void initState() {
    super.initState();
    _fetchLatestTelemetry();
    _startTimer();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      final bool hasNetwork = !result.contains(ConnectivityResult.none);
      if (!hasNetwork && _isOnline) {
        _isOnline = false;
        _liveTimer?.cancel();
        debugPrint('⚠️ 明細數據頁斷網，停止刷新');
      } else if (hasNetwork && !_isOnline) {
        _isOnline = true;
        _fetchLatestTelemetry();
        _startTimer();
      }
    });
  }

  void _startTimer() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchLatestTelemetry(isSilent: true));
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLatestTelemetry({bool isSilent = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    if (!isSilent) setState(() => _isLoading = true);

    try {
      if (widget.deviceDbId.isEmpty) return;

      final devRes = await Supabase.instance.client
          .from('devices')
          .select('sn')
          .eq('id', widget.deviceDbId)
          .maybeSingle();

      if (devRes == null) return;
      final String sn = (devRes['sn'] ?? '').toString();

      if (sn.isEmpty) return;

      final List<dynamic> list = await Supabase.instance.client
          .from('telemetry_test')
          .select()
          .eq('device_id', sn)
          .order('created_at', ascending: false)
          .limit(1);

      final List<dynamic> invPsList = await Supabase.instance.client
          .from('telemetry_inv_ps')
          .select('ac_out_power_percentage') 
          .eq('device_id', sn)
          .order('created_at', ascending: false)
          .limit(1);

      if (mounted) {
        setState(() {
          _telemetryData = list.isNotEmpty ? (list.first as Map<String, dynamic>) : null;
          _invPsData = invPsList.isNotEmpty ? (invPsList.first as Map<String, dynamic>) : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    } finally {
      _isFetching = false;
    }
  }

  void _showHistoryDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => HistoryDataModal(deviceDbId: widget.deviceDbId),
    );
  }

  @override
  Widget build(BuildContext context) {
    double v1 = double.tryParse((_telemetryData?['pv1_voltage'] ?? 0).toString()) ?? 0.0;
    double i1 = double.tryParse((_telemetryData?['pv1_current'] ?? 0).toString()) ?? 0.0;
    double v2 = double.tryParse((_telemetryData?['pv2_voltage'] ?? 0).toString()) ?? 0.0;
    double i2 = double.tryParse((_telemetryData?['pv2_current'] ?? 0).toString()) ?? 0.0;
    double totalPvWatts = (v1 * i1) + (v2 * i2);

    return Scaffold(
      backgroundColor: Colors.white, 
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: const Text('數據明細', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.teal.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _showHistoryDialog,
              icon: const Icon(Icons.history_rounded, size: 16, color: Colors.teal),
              label: const Text('歷史數據', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)))
          : RefreshIndicator(
              onRefresh: () => _fetchLatestTelemetry(),
              color: Colors.teal,
              child: ListView(
                padding: const EdgeInsets.all(16), 
                children: [
                  _buildExpandableCategory(
                    title: '電網 (Grid)',
                    icon: Icons.electrical_services_rounded,
                    color: const Color(0xFF0EA5E9),
                    items: [
                      _buildDataRow('L1 市電電壓', '${_telemetryData?['ac_in_v_r'] ?? '--'} V'),
                      _buildDataRow('L2 市電電壓', '${_telemetryData?['ac_in_v_s'] ?? '--'} V'),
                      _buildDataRow('市電頻率', '${_telemetryData?['ac_in_freq'] ?? '--'} Hz'),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _buildExpandableCategory(
                    title: '電池 (Battery)',
                    icon: Icons.battery_charging_full_rounded,
                    color: const Color(0xFF10B981),
                    items: [
                      _buildDataRow('電池容量 (SOC)', '${_telemetryData?['battery_capacity'] ?? '--'} %'),
                      _buildDataRow('電池電壓', '${_telemetryData?['battery_voltage'] ?? '--'} V'),
                      _buildDataRow('充/放電電流', '${_telemetryData?['battery_current'] ?? '--'} A'),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _buildExpandableCategory(
                    title: '太陽能 (Solar PV)',
                    icon: Icons.wb_sunny_rounded,
                    color: const Color(0xFFF59E0B),
                    items: [
                      _buildDataRow('Solar 1 電壓', '${_telemetryData?['pv1_voltage'] ?? '--'} V'),
                      _buildDataRow('Solar 1 電流', '${_telemetryData?['pv1_current'] ?? '--'} A'),
                      _buildDataRow('Solar 2 電壓', '${_telemetryData?['pv2_voltage'] ?? '--'} V'),
                      _buildDataRow('Solar 2 電流', '${_telemetryData?['pv2_current'] ?? '--'} A'),
                      _buildDataRow('太陽能總功率', _telemetryData != null ? '${totalPvWatts.toStringAsFixed(1)} W' : '-- W'),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _buildExpandableCategory(
                    title: '負載 (Load)',
                    icon: Icons.home_max_rounded,
                    color: const Color(0xFF3B82F6),
                    items: [
                      _buildDataRow('L1 輸出電壓', '${_telemetryData?['ac_out_v_r'] ?? '--'} V'),
                      _buildDataRow('L2 輸出電壓', '${_telemetryData?['ac_out_v_s'] ?? '--'} V'),
                      _buildDataRow('頻率', '${_telemetryData?['ac_out_freq'] ?? '--'} Hz'),
                      _buildDataRow('負載量', '${_invPsData?['ac_out_power_percentage'] ?? '--'} %'),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _buildExpandableCategory(
                    title: '其他',
                    icon: Icons.thermostat_rounded,
                    color: const Color(0xFF8B5CF6),
                    items: [
                      _buildDataRow('機身內部溫度', '${_telemetryData?['inner_temp'] ?? '--'} ℃'),
                      _buildDataRow('最高組件溫度', '${_telemetryData?['comp_max_temp'] ?? '--'} ℃'),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildExpandableCategory({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color, size: 18),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
          children: [
            const Divider(color: Color(0xFFF1F5F9), height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(children: items),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class HistoryDataModal extends StatefulWidget {
  final String deviceDbId;
  const HistoryDataModal({super.key, required this.deviceDbId});

  @override
  State<HistoryDataModal> createState() => _HistoryDataModalState();
}

class _HistoryDataModalState extends State<HistoryDataModal> {
  DateTime _selectedDate = DateTime.now();
  DateTime? _earliestDataDate; 
  
  int _startHour = 0;
  int _endHour = 24;

  bool _isLoadingList = true;
  List<Map<String, dynamic>> _historyLogs = [];
  Map<String, dynamic>? _selectedLog;
  List<Map<String, dynamic>> _historyInvPsLogs = []; 
  Map<String, dynamic>? _selectedInvPsLog;

  @override
  void initState() {
    super.initState();
    _fetchHistoryLogs();
  }

  String _twoDigits(int n) => n >= 10 ? "$n" : "0$n";

  Future<void> _fetchHistoryLogs() async {
    setState(() => _isLoadingList = true);

    try {
      if (widget.deviceDbId.isEmpty) return;

      final devRes = await Supabase.instance.client
          .from('devices')
          .select('sn')
          .eq('id', widget.deviceDbId)
          .maybeSingle();

      if (devRes == null) return;
      final String sn = (devRes['sn'] ?? '').toString();
      if (sn.isEmpty) return;

      if (_earliestDataDate == null) {
        final earliestRes = await Supabase.instance.client
            .from('telemetry_test')
            .select('created_at')
            .eq('device_id', sn)
            .order('created_at', ascending: true)
            .limit(1);
        if (earliestRes.isNotEmpty) {
          String rawTime = earliestRes.first['created_at'].toString();
          if (rawTime.length >= 19) {
            _earliestDataDate = DateTime.parse(rawTime.substring(0, 19)); 
          }
        }
      }

      final String dateFormatted = "${_selectedDate.year}-${_twoDigits(_selectedDate.month)}-${_twoDigits(_selectedDate.day)}";
      
      final String timeStartStr = "${_twoDigits(_startHour)}:00:00.000";
      String timeEndStr;
      if (_endHour == 0) {
        timeEndStr = "00:00:00.000";
      } else if (_endHour == 24) {
        timeEndStr = "23:59:59.999";
      } else {
        timeEndStr = "${_twoDigits(_endHour - 1)}:59:59.999";
      }

      final String dayStart = "${dateFormatted}T$timeStartStr";
      final String dayEnd = "${dateFormatted}T$timeEndStr";

      final List<dynamic> response = await Supabase.instance.client
          .from('telemetry_test')
          .select()
          .eq('device_id', sn)
          .gte('created_at', dayStart)
          .lte('created_at', dayEnd)
          .order('created_at', ascending: false)
          .limit(1500); 

      final List<dynamic> invPsResponse = await Supabase.instance.client
          .from('telemetry_inv_ps')
          .select('created_at, ac_out_power_percentage') 
          .eq('device_id', sn)
          .gte('created_at', dayStart)
          .lte('created_at', dayEnd)
          .order('created_at', ascending: false)
          .limit(1500); 

      if (mounted) {
        setState(() {
          _historyLogs = response.map((item) => Map<String, dynamic>.from(item as Map)).toList();
          _historyInvPsLogs = invPsResponse.map((item) => Map<String, dynamic>.from(item as Map)).toList();
          _selectedLog = _historyLogs.isNotEmpty ? _historyLogs.first : null;
          _selectedInvPsLog = _historyInvPsLogs.isNotEmpty ? _historyInvPsLogs.first : null;
          _isLoadingList = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingList = false);
    }
  }

  String _formatTimeOnly(String? rawTime) {
    if (rawTime == null || rawTime.isEmpty) return '--:--:--';
    try {
      DateTime dt = DateTime.parse(rawTime);
      return "${_twoDigits(dt.hour)}:${_twoDigits(dt.minute)}:${_twoDigits(dt.second)}";
    } catch (e) {
      return rawTime.length >= 19 ? rawTime.substring(11, 19) : '--:--:--';
    }
  }

  String _formatFullDateTime(String? rawTime) {
    if (rawTime == null || rawTime.isEmpty) return '--/--/-- --:--:--';
    try {
      DateTime dt = DateTime.parse(rawTime);
      return "${dt.year}/${_twoDigits(dt.month)}/${_twoDigits(dt.day)} ${_twoDigits(dt.hour)}:${_twoDigits(dt.minute)}:${_twoDigits(dt.second)}";
    } catch (e) {
      return rawTime.replaceAll('T', ' ').substring(0, 19);
    }
  }

  void _resetTimeRange() {
    _startHour = 0;
    _endHour = 24;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context, 
      initialDate: _selectedDate, 
      firstDate: _earliestDataDate ?? DateTime(2020), 
      lastDate: now, 
    );
    if (picked != null && picked != _selectedDate) {
      setState(() { 
        _selectedDate = picked; 
        _resetTimeRange(); 
      });
      _fetchHistoryLogs();
    }
  }

  void _goPrevDay() {
    final prevDate = _selectedDate.subtract(const Duration(days: 1));
    final prevDateOnly = DateTime(prevDate.year, prevDate.month, prevDate.day);

    if (_earliestDataDate != null) {
      final earliestOnly = DateTime(_earliestDataDate!.year, _earliestDataDate!.month, _earliestDataDate!.day);
      if (prevDateOnly.isBefore(earliestOnly)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('該日期無歷史資料'), duration: Duration(seconds: 2)),
        );
        return;
      }
    }
    setState(() { 
      _selectedDate = prevDate; 
      _resetTimeRange(); 
    });
    _fetchHistoryLogs();
  }

  void _goNextDay() {
    final nextDate = _selectedDate.add(const Duration(days: 1));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextDateOnly = DateTime(nextDate.year, nextDate.month, nextDate.day);

    if (nextDateOnly.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法選擇未來的日期時間'), duration: Duration(seconds: 2)),
      );
      return;
    }
    setState(() { 
      _selectedDate = nextDate; 
      _resetTimeRange(); 
    });
    _fetchHistoryLogs();
  }

  Widget _buildHourDropdown(bool isStart) {
    int currentValue = isStart ? _startHour : _endHour;
    int itemCount = isStart ? 24 : 25; 

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: currentValue,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.teal),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal),
          items: List.generate(itemCount, (index) {
            return DropdownMenuItem<int>(
              value: index,
              child: Text("${_twoDigits(index)}:00"),
            );
          }),
          onChanged: (int? newValue) {
            if (newValue != null) {
              setState(() {
                if (isStart) {
                  _startHour = newValue;
                  if (_startHour > _endHour) _endHour = _startHour;
                } else {
                  _endHour = newValue;
                  if (_endHour < _startHour) _startHour = _endHour;
                }
              });
              _fetchHistoryLogs();
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String dateStr = "${_selectedDate.year}-${_twoDigits(_selectedDate.month)}-${_twoDigits(_selectedDate.day)}";

    bool isPrevDisabled = false;
    if (_earliestDataDate != null) {
      final prevDateOnly = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).subtract(const Duration(days: 1));
      final earliestOnly = DateTime(_earliestDataDate!.year, _earliestDataDate!.month, _earliestDataDate!.day);
      if (prevDateOnly.isBefore(earliestOnly)) isPrevDisabled = true;
    }

    bool isNextDisabled = false;
    final nextDateOnly = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).add(const Duration(days: 1));
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (nextDateOnly.isAfter(today)) isNextDisabled = true;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('歷史數據列表', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: Colors.black45),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const SizedBox(height: 10),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.circular(30), 
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))
              ]
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: _goPrevDay,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Icon(Icons.chevron_left_rounded, size: 24, color: isPrevDisabled ? Colors.grey[300] : Colors.teal)
                  ),
                ),
                const SizedBox(width: 16),
                InkWell(
                  onTap: () => _selectDate(context),
                  child: Text(dateStr, style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                InkWell(
                  onTap: _goNextDay,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Icon(Icons.chevron_right_rounded, size: 24, color: isNextDisabled ? Colors.grey[300] : Colors.teal)
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_time_rounded, size: 16, color: Colors.black45),
              const SizedBox(width: 8),
              _buildHourDropdown(true),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0),
                child: Text("至", style: TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              _buildHourDropdown(false),
            ],
          ),
          const SizedBox(height: 14),

          _isLoadingList
              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal))))
              : _historyLogs.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8)),
                      child: const Text('該時段區間尚無歷史資料。', style: TextStyle(color: Colors.black38, fontSize: 12), textAlign: TextAlign.center),
                    )
                  : SizedBox(
                      height: 38,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _historyLogs.length,
                        itemBuilder: (context, index) {
                          final log = _historyLogs[index];
                          final bool isSelected = _selectedLog == log;
                          final timeStr = _formatTimeOnly(log['created_at']?.toString());

                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text(timeStr, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                              selected: isSelected,
                              selectedColor: Colors.teal,
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20), 
                                side: BorderSide(color: isSelected ? Colors.teal : Colors.grey.shade200)
                              ),
                              onSelected: (val) {
                                setState(() { 
                                  _selectedLog = log;
                                  _selectedInvPsLog = index < _historyInvPsLogs.length ? _historyInvPsLogs[index] : null; 
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 12),

          Expanded(
            child: _selectedLog == null
                ? const Center(child: Text('請點選上方時間點檢視數據', style: TextStyle(color: Colors.black38)))
                : ListView(
                    children: [
                      Text(
                        '🕒 紀錄時間：${_formatFullDateTime(_selectedLog!['created_at']?.toString())}', 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)
                      ),
                      const SizedBox(height: 12),

                      _buildHistoryCategoryCard('⚡ 電網 (Grid)', [
                        _buildMetricItem('L1 市電電壓', '${_selectedLog!['ac_in_v_r'] ?? '--'} V'),
                        _buildMetricItem('L2 市電電壓', '${_selectedLog!['ac_in_v_s'] ?? '--'} V'),
                        _buildMetricItem('市電頻率', '${_selectedLog!['ac_in_freq'] ?? '--'} Hz'),
                      ]),
                      const SizedBox(height: 12),

                      _buildHistoryCategoryCard('🔋 電池 (Battery)', [
                        _buildMetricItem('電池容量 (SOC)', '${_selectedLog!['battery_capacity'] ?? '--'} %'),
                        _buildMetricItem('電池電壓', '${_selectedLog!['battery_voltage'] ?? '--'} V'),
                        _buildMetricItem('充/放電電流', '${_selectedLog!['battery_current'] ?? '--'} A'),
                      ]),
                      const SizedBox(height: 12),

                      _buildHistoryCategoryCard('☀️ 太陽能 (Solar PV)', [
                        _buildMetricItem('Solar 1 電壓', '${_selectedLog!['pv1_voltage'] ?? '--'} V'),
                        _buildMetricItem('Solar 1 電流', '${_selectedLog!['pv1_current'] ?? '--'} A'),
                        _buildMetricItem('Solar 2 電壓', '${_selectedLog!['pv2_voltage'] ?? '--'} V'),
                        _buildMetricItem('Solar 2 電流', '${_selectedLog!['pv2_current'] ?? '--'} A'),
                      ]),
                      const SizedBox(height: 12),

                      _buildHistoryCategoryCard('🏠 負載 (Load)', [
                        _buildMetricItem('L1 輸出電壓', '${_selectedLog!['ac_out_v_r'] ?? '--'} V'),
                        _buildMetricItem('L2 輸出電壓', '${_selectedLog!['ac_out_v_s'] ?? '--'} V'),
                        _buildMetricItem('頻率', '${_selectedLog!['ac_out_freq'] ?? '--'} Hz'),
                        _buildMetricItem('負載量', '${_selectedInvPsLog?['ac_out_power_percentage'] ?? '--'} %'),
                      ]),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCategoryCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), 
            blurRadius: 10, 
            offset: const Offset(0, 4)
          )
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
          const SizedBox(height: 10),
          Column(children: children),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class AlarmListScreen extends StatefulWidget {
  final String deviceDbId;
  const AlarmListScreen({super.key, required this.deviceDbId});

  @override
  State<AlarmListScreen> createState() => _AlarmListScreenState();
}

class _AlarmListScreenState extends State<AlarmListScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<Map<String, dynamic>> _alarmList = [];
  List<Map<String, dynamic>> _faultList = []; // 🎯 新增：錯誤清單
  String _filterMode = '全部'; 
  
  late TabController _tabController; // 🎯 新增：標籤控制器
  Timer? _alarmTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchAlarmsFromSupabase();
    _startTimer();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      final bool hasNetwork = !result.contains(ConnectivityResult.none);
      if (!hasNetwork && _isOnline) {
        _isOnline = false;
        _alarmTimer?.cancel();
      } else if (hasNetwork && !_isOnline) {
        _isOnline = true;
        _fetchAlarmsFromSupabase();
        _startTimer();
      }
    });
  }

  void _startTimer() {
    _alarmTimer?.cancel();
    _alarmTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchAlarmsFromSupabase(isSilent: true));
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _alarmTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // 🎯 共用的過濾邏輯
  List<Map<String, dynamic>> _getFilteredList(List<Map<String, dynamic>> sourceList) {
    if (_filterMode == '處理中') {
      return sourceList.where((alarm) => alarm['is_active'] == true).toList();
    } else if (_filterMode == '已解除') {
      return sourceList.where((alarm) => alarm['is_active'] == false).toList();
    }
    return sourceList; 
  }

  Future<void> _fetchAlarmsFromSupabase({bool isSilent = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    if (!isSilent) setState(() => _isLoading = true);

    try {
      if (widget.deviceDbId.isEmpty) return;

      final devRes = await Supabase.instance.client
          .from('devices')
          .select('sn')
          .eq('id', widget.deviceDbId)
          .maybeSingle();

      if (devRes == null) return;
      final String sn = (devRes['sn'] ?? '').toString();
      if (sn.isEmpty) return;

      final List<dynamic> alarmLogs = await Supabase.instance.client
          .from('device_alarms')
          .select('alarm_code, alarm_message, is_active, created_at_tw, resolved_at_tw, created_at')
          .eq('device_id', sn)
          .order('created_at', ascending: false) 
          .limit(100);

      List<Map<String, dynamic>> parsedAlarms = [];
      List<Map<String, dynamic>> parsedFaults = [];

      for (var log in alarmLogs) {
        // 🎯 核心判斷：如果 alarm_code 都是數字，代表它是系統錯誤 (Faults 01-32)
        final bool isFault = RegExp(r'^[0-9]+$').hasMatch(log['alarm_code'] ?? '');
        
        final item = {
          'time': log['created_at_tw'] ?? '',
          'resolved_time': log['resolved_at_tw'] ?? '',
          'status': log['alarm_message'] ?? '未知狀態',
          'is_active': log['is_active'] == true,
        };

        if (isFault) {
          parsedFaults.add(item);
        } else {
          parsedAlarms.add(item);
        }
      }

      if (mounted) {
        setState(() {
          _alarmList = parsedAlarms;
          _faultList = parsedFaults;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    } finally {
      _isFetching = false;
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

  // 🎯 共用的列表渲染元件
  Widget _buildListView(List<Map<String, dynamic>> sourceList, String emptyMessage) {
    final filteredList = _getFilteredList(sourceList);

    return RefreshIndicator(
      onRefresh: () => _fetchAlarmsFromSupabase(),
      color: Colors.teal,
      child: sourceList.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 48),
                      const SizedBox(height: 12),
                      Text('太棒了！儲能系統運轉順暢，無任何$emptyMessage紀錄。', style: const TextStyle(color: Colors.black45, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            )
          : filteredList.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.inbox_rounded, color: Colors.grey[300], size: 48),
                          const SizedBox(height: 12),
                          Text('目前沒有「$_filterMode」的$emptyMessage紀錄', style: const TextStyle(color: Colors.black45, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredList.length,
                  itemBuilder: (context, index) {
                    final item = filteredList[index];
                    final bool isActive = item['is_active'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: isActive ? Colors.red.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 4)
                          )
                        ]
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: isActive ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                              child: Icon(isActive ? Icons.error_outline : Icons.check_circle_outline, color: isActive ? Colors.red : Colors.green, size: 20),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['status'],
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isActive ? Colors.red[900] : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time_rounded, size: 12, color: Colors.black38),
                                      const SizedBox(width: 4),
                                      Text('發生: ${item['time']}', style: const TextStyle(color: Colors.black54, fontSize: 11)),
                                    ],
                                  ),
                                  if (!isActive && item['resolved_time'].isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.task_alt_rounded, size: 12, color: Colors.teal),
                                        const SizedBox(width: 4),
                                        Text('解除: ${item['resolved_time']}', style: const TextStyle(color: Colors.teal, fontSize: 11, fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.red : Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isActive ? '處理中' : '已解除',
                                style: TextStyle(
                                  color: isActive ? Colors.white : Colors.black45,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white, 
        appBar: AppBar(
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          title: const Text('系統告警與錯誤紀錄', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.teal,
            labelColor: Colors.teal,
            unselectedLabelColor: Colors.black54,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            tabs: const [ Tab(text: '告警'), Tab(text: '錯誤') ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)))
            : Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.white,
                    child: Row(
                      children: [
                        _buildFilterChip('全部'),
                        _buildFilterChip('處理中'),
                        _buildFilterChip('已解除'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildListView(_alarmList, '告警'),
                        _buildListView(_faultList, '錯誤'),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}