import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/chart_painters.dart'; 

class AnalysisScreen extends StatefulWidget {
  final String deviceDbId;
  const AnalysisScreen({super.key, required this.deviceDbId});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime selectedDate = DateTime.now();
  DateTime? _earliestDataDate; 

  Map<String, dynamic>? _dailyEnergyStats;
  Map<String, dynamic>? _realtimeLatestTest;
  Map<String, dynamic>? _realtimeLatestInvPs;

  List<Map<String, dynamic>> _historyTelemetryList = [];
  List<Map<String, dynamic>> _historyInvPsList = [];

  bool _isLoadingData = true;
  Timer? _realtimeRefreshTimer;
  Offset? _touchPosition;

  String _tariffMode = '一般累進表燈(住商)';
  List<Map<String, dynamic>> _dailySavingsData = [];
  double _monthlySavings = 0.0;
  double _yearlySavings = 0.0;
  bool _isLoadingSavings = true;

  String _formatPower(double? watts) {
    if (watts == null) return '--';
    if (watts >= 1000) return '${(watts / 1000.0).toStringAsFixed(2)} kW';
    return '${watts.toStringAsFixed(0)} W';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() { _touchPosition = null; });
      }
    });

    _fetchRealtimeLatestAndHistoryData();
    _realtimeRefreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchRealtimeLatestAndHistoryData(isSilent: true);
    });
  }

  @override
  void dispose() {
    _realtimeRefreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchRealtimeLatestAndHistoryData({bool isSilent = false}) async {
    if (!isSilent) setState(() { _isLoadingData = true; });
    try {
      if (widget.deviceDbId.isEmpty) return;
      final devRes = await Supabase.instance.client.from('devices').select('sn, electricity_tariff').eq('id', widget.deviceDbId).maybeSingle();
      if (devRes == null) return;
      final String sn = (devRes['sn'] ?? '').toString();
      if (sn.isEmpty) return;

      _tariffMode = devRes['electricity_tariff'] ?? '一般累進表燈(住商)';
      _fetchSavingsData(sn, isSilent: isSilent);

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

      final dateFormatted = "${selectedDate.year}-${_twoDigits(selectedDate.month)}-${_twoDigits(selectedDate.day)}";
      final dayStart = "${dateFormatted}T00:00:00.000Z";
      final dayEnd = "${dateFormatted}T23:59:59.999Z";

      final latestTest = await Supabase.instance.client.from('telemetry_test').select().eq('device_id', sn).order('created_at', ascending: false).limit(1);
      final latestInvPs = await Supabase.instance.client.from('telemetry_inv_ps').select().eq('device_id', sn).order('created_at', ascending: false).limit(1);
      final dailyStats = await Supabase.instance.client.from('daily_energy_stats').select().eq('device_id', sn).eq('date', dateFormatted).limit(1);
      
      final historyTest = await Supabase.instance.client.from('telemetry_test').select().eq('device_id', sn).gte('created_at', dayStart).lte('created_at', dayEnd).order('created_at', ascending: true).limit(1000);
      final historyInvPs = await Supabase.instance.client.from('telemetry_inv_ps').select().eq('device_id', sn).gte('created_at', dayStart).lte('created_at', dayEnd).order('created_at', ascending: true).limit(1000);

      if (mounted) {
        setState(() {
          _realtimeLatestTest = latestTest.isNotEmpty ? latestTest.first : null;
          _realtimeLatestInvPs = latestInvPs.isNotEmpty ? latestInvPs.first : null;
          _dailyEnergyStats = dailyStats.isNotEmpty ? dailyStats.first : null;
          _historyTelemetryList = historyTest.map((item) => Map<String, dynamic>.from(item as Map)).toList();
          _historyInvPsList = historyInvPs.map((item) => Map<String, dynamic>.from(item as Map)).toList();
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoadingData = false; });
    }
  }

  Future<void> _fetchSavingsData(String sn, {bool isSilent = false}) async {
    if (!isSilent) {
      setState(() { _isLoadingSavings = true; });
    }
    
    try {
      final dayStart = "${selectedDate.year}-${_twoDigits(selectedDate.month)}-${_twoDigits(selectedDate.day)} 00:00:00";
      final dayEnd = "${selectedDate.year}-${_twoDigits(selectedDate.month)}-${_twoDigits(selectedDate.day)} 23:59:59";
      
      final monthStart = "${selectedDate.year}-${_twoDigits(selectedDate.month)}-01 00:00:00";
      final lastDayOfMonth = DateTime(selectedDate.year, selectedDate.month + 1, 0).day;
      final monthEnd = "${selectedDate.year}-${_twoDigits(selectedDate.month)}-${_twoDigits(lastDayOfMonth)} 23:59:59";

      final yearStart = "${selectedDate.year}-01-01 00:00:00";
      final yearEnd = "${selectedDate.year}-12-31 23:59:59";

      final results = await Future.wait([
        Supabase.instance.client.rpc('calculate_hourly_solar_savings', params: { 'target_device_id': sn, 'tariff_type': _tariffMode, 'start_time': dayStart, 'end_time': dayEnd }),
        Supabase.instance.client.rpc('calculate_hourly_solar_savings', params: { 'target_device_id': sn, 'tariff_type': _tariffMode, 'start_time': monthStart, 'end_time': monthEnd }),
        Supabase.instance.client.rpc('calculate_hourly_solar_savings', params: { 'target_device_id': sn, 'tariff_type': _tariffMode, 'start_time': yearStart, 'end_time': yearEnd }),
      ]);

      double mTotal = 0;
      for(var r in (results[1] as List)) { mTotal += double.tryParse(r['saved_twd'].toString()) ?? 0; }
      
      double yTotal = 0;
      for(var r in (results[2] as List)) { yTotal += double.tryParse(r['saved_twd'].toString()) ?? 0; }

      List<Map<String, dynamic>> parsedDay = [];
      for (var row in (results[0] as List)) {
        parsedDay.add({
          'hour': row['hour_of_day'],
          'saved': double.tryParse(row['saved_twd'].toString()) ?? 0.0,
          'period': row['tou_period'],
        });
      }
      parsedDay.sort((a, b) => (a['hour'] as int).compareTo(b['hour'] as int));

      if (mounted) {
        setState(() {
          _monthlySavings = mTotal;
          _yearlySavings = yTotal;
          _dailySavingsData = parsedDay;
          _isLoadingSavings = false;
        });
      }
    } catch(e) {
      if (mounted) setState(() { _isLoadingSavings = false; });
    }
  }

  String _twoDigits(int n) => n >= 10 ? "$n" : "0$n";

  Future<void> _selectDate(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context, 
      initialDate: selectedDate, 
      firstDate: _earliestDataDate ?? DateTime(2020), 
      lastDate: now, 
    );
    if (picked != null && picked != selectedDate) {
      setState(() { selectedDate = picked; _touchPosition = null; });
      _fetchRealtimeLatestAndHistoryData();
    }
  }

  void _goPrevDay() {
    final prevDate = selectedDate.subtract(const Duration(days: 1));
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
    setState(() { selectedDate = prevDate; _touchPosition = null; });
    _fetchRealtimeLatestAndHistoryData();
  }

  void _goNextDay() {
    final nextDate = selectedDate.add(const Duration(days: 1));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextDateOnly = DateTime(nextDate.year, nextDate.month, nextDate.day);

    if (nextDateOnly.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法選擇未來的日期時間'), duration: Duration(seconds: 2)),
      );
      return;
    }
    setState(() { selectedDate = nextDate; _touchPosition = null; });
    _fetchRealtimeLatestAndHistoryData();
  }

  @override
  Widget build(BuildContext context) {
    String dateStr = "${selectedDate.year}-${_twoDigits(selectedDate.month)}-${_twoDigits(selectedDate.day)}";
    
    bool isPrevDisabled = false;
    if (_earliestDataDate != null) {
      final prevDateOnly = DateTime(selectedDate.year, selectedDate.month, selectedDate.day).subtract(const Duration(days: 1));
      final earliestOnly = DateTime(_earliestDataDate!.year, _earliestDataDate!.month, _earliestDataDate!.day);
      if (prevDateOnly.isBefore(earliestOnly)) isPrevDisabled = true;
    }

    bool isNextDisabled = false;
    final nextDateOnly = DateTime(selectedDate.year, selectedDate.month, selectedDate.day).add(const Duration(days: 1));
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (nextDateOnly.isAfter(today)) isNextDisabled = true;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.teal,
                labelColor: Colors.teal,
                unselectedLabelColor: Colors.black54,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                tabs: const [ Tab(text: '總覽'), Tab(text: '住宅'), Tab(text: '太陽能'), Tab(text: '電池'), Tab(text: '電網') ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Container(
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
            ),
            Expanded(
              child: _isLoadingData
                  ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)))
                  : TabBarView(
                      physics: const NeverScrollableScrollPhysics(), 
                      controller: _tabController,
                      children: [
                        _buildOverviewTab(),
                        _buildHomeTab(),
                        _buildSolarTab(), 
                        _buildBatteryTab(),
                        _buildGridTab(),
                      ],
                    ),
            ),
          ],
        ),
      )
    );
  }

  Widget _buildOverviewTab() {
    double pvWatts = 0.0;
    if (_realtimeLatestInvPs != null) {
      double s1 = double.tryParse((_realtimeLatestInvPs!['solar1_input_power'] ?? 0).toString()) ?? 0.0;
      double s2 = double.tryParse((_realtimeLatestInvPs!['solar2_input_power'] ?? 0).toString()) ?? 0.0;
      pvWatts = s1 + s2;
    }
    
    String loadPercentage = _realtimeLatestInvPs?['ac_out_power_percentage'] != null ? '${_realtimeLatestInvPs!['ac_out_power_percentage']} %' : '--';

    double? parseValue(dynamic val) => val != null ? double.tryParse(val.toString()) : null;
    
    double? valLoad = parseValue(_dailyEnergyStats?['today_load_kwh']);
    double? valGrid = parseValue(_dailyEnergyStats?['today_grid_kwh']);

    String todayLoadStr = valLoad != null ? '${valLoad.toStringAsFixed(2)} kWh' : '--';
    String todayGridStr = valGrid != null ? '${valGrid.toStringAsFixed(2)} kWh' : '--';

    double loadKwh = valLoad ?? 0.0;
    double gridKwh = valGrid ?? 0.0;
    double selfConsumptionRatio = 0.0;
    if (loadKwh > 0) {
      selfConsumptionRatio = ((1 - (gridKwh / loadKwh)) * 100).clamp(0.0, 100.0);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14.0),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.circular(16), 
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06), 
                  blurRadius: 16, 
                  offset: const Offset(0, 6)
                )
              ]
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('自我供電', style: TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${selfConsumptionRatio.toStringAsFixed(1)} %', style: const TextStyle(color: Colors.teal, fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('計算公式: [1-(電網/負載)] *100%', style: TextStyle(color: Colors.grey[400], fontSize: 8)),
                  ],
                ),
                SizedBox(
                  width: 80, height: 80,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: selfConsumptionRatio / 100,
                        strokeWidth: 10,
                        backgroundColor: Colors.grey[100],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                      ),
                      Center(child: Icon(Icons.flash_on_rounded, color: Colors.orangeAccent.withValues(alpha: 0.5), size: 32)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildWhiteMetricCard('今日購電量(電網)', todayGridStr),
              _buildWhiteMetricCard('今日用電量(負載)', todayLoadStr),
              _buildWhiteMetricCard('太陽能功率', _formatPower(pvWatts)),
              _buildWhiteMetricCard('負載量', loadPercentage),
            ],
          ),
          const SizedBox(height: 16),
          _buildInteractiveChartContainer('overview', [
            MapEntry(const Color(0xFF3B82F6), '負載 (W)'),
            MapEntry(const Color(0xFFF59E0B), '太陽能 (W)'),
            MapEntry(const Color(0xFFFF5252), '電網 (W)'),
            MapEntry(const Color(0xFF10B981), '電池 (W)'),
          ], maxY: 12.0),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    String acOutVR = _realtimeLatestTest?['ac_out_v_r'] != null ? '${_realtimeLatestTest!['ac_out_v_r']} V' : '--';
    String acOutVS = _realtimeLatestTest?['ac_out_v_s'] != null ? '${_realtimeLatestTest!['ac_out_v_s']} V' : '--';
    String acOutFreq = _realtimeLatestTest?['ac_out_freq'] != null ? '${_realtimeLatestTest!['ac_out_freq']} Hz' : '--';
    
    // 🎯 讀取「輸出功率」來替換原本的負載百分比
    double? acOutW = _realtimeLatestInvPs?['ac_out_total_active_power'] != null 
        ? double.tryParse(_realtimeLatestInvPs!['ac_out_total_active_power'].toString()) 
        : null;
    String acOutWStr = _formatPower(acOutW);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14.0),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildWhiteMetricCard('L1輸出電壓', acOutVR),
              _buildWhiteMetricCard('L2輸出電壓', acOutVS),
              _buildWhiteMetricCard('輸出頻率', acOutFreq),
              // 🎯 替換成輸出功率 (W/kW)
              _buildWhiteMetricCard('輸出功率', acOutWStr),
            ],
          ),
          const SizedBox(height: 16),
          // 🎯 更新圖例名稱與新指定的顏色 (淺棕/極淺棕/藍)
          _buildInteractiveChartContainer('home', [
            MapEntry(const Color(0xFFC4A484), 'L1輸出電壓 (V)'),
            MapEntry(const Color(0xFFE5D3B3), 'L2輸出電壓 (V)'),
            MapEntry(const Color(0xFF2563EB), '輸出功率 (W)'),
          ]),
        ],
      ),
    );
  }

  Widget _buildSolarTab() {
    String pv1W = _realtimeLatestInvPs?['solar1_input_power'] != null ? '${_realtimeLatestInvPs!['solar1_input_power']} W' : '--';
    String pv2W = _realtimeLatestInvPs?['solar2_input_power'] != null ? '${_realtimeLatestInvPs!['solar2_input_power']} W' : '--';
    
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14.0),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildWhiteMetricCard('MPPT 1發電功率', pv1W),
              _buildWhiteMetricCard('MPPT 2發電功率', pv2W),
              _buildWhiteMetricCard('本月總收益', 'NT\$ ${_monthlySavings.toStringAsFixed(1)}'),
              _buildWhiteMetricCard('本年總收益', 'NT\$ ${_yearlySavings.toStringAsFixed(1)}'),
            ],
          ),
          const SizedBox(height: 16),
          _buildSavingsChartContainer(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSavingsChartContainer() {
    double maxS = 10.0;
    double dailyTotal = 0.0; 

    for (var d in _dailySavingsData) {
      if (d['saved'] > maxS) maxS = d['saved'] as double;
      dailyTotal += (d['saved'] as double); 
    }
    maxS = (maxS * 1.2).ceilToDouble(); 

    return Container(
      width: double.infinity,
      height: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), 
            blurRadius: 12, 
            offset: const Offset(0, 4)
          )
        ]
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '本日發電總收益：NT\$ ${dailyTotal.toStringAsFixed(1)}', 
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.teal) 
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoadingSavings 
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)))
              : _dailySavingsData.isEmpty
                ? const Center(child: Text('此日期尚無收益數據', style: TextStyle(color: Colors.black38, fontSize: 13)))
                : GestureDetector(
                    onPanUpdate: (details) { setState(() { _touchPosition = details.localPosition; }); },
                    onPanDown: (details) { setState(() { _touchPosition = details.localPosition; }); },
                    onPanEnd: (details) { setState(() { _touchPosition = null; }); },
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: SavingsBarChartPainter(
                        savingsData: _dailySavingsData,
                        touchPosition: _touchPosition,
                        maxSavings: maxS,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(Colors.redAccent.shade200, '尖峰'),
              const SizedBox(width: 12),
              _buildLegendItem(Colors.orangeAccent, '半尖峰'),
              const SizedBox(width: 12),
              _buildLegendItem(Colors.teal.shade300, '離峰'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildBatteryTab() {
    String batCap = _realtimeLatestTest?['battery_capacity'] != null ? '${_realtimeLatestTest!['battery_capacity']} %' : '--';
    String batV = _realtimeLatestTest?['battery_voltage'] != null ? '${_realtimeLatestTest!['battery_voltage']} V' : '--';
    String batI = _realtimeLatestTest?['battery_current'] != null ? '${_realtimeLatestTest!['battery_current']} A' : '--';

    double? chargeKwh = _dailyEnergyStats?['today_charge_kwh'] != null ? double.tryParse(_dailyEnergyStats!['today_charge_kwh'].toString()) : null;
    double? dischargeKwh = _dailyEnergyStats?['today_discharge_kwh'] != null ? double.tryParse(_dailyEnergyStats!['today_discharge_kwh'].toString()) : null;
    String chargeStr = chargeKwh != null ? '${chargeKwh.toStringAsFixed(2)} kWh' : '--';
    String dischargeStr = dischargeKwh != null ? '${dischargeKwh.toStringAsFixed(2)} kWh' : '--';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildWhiteMetricCard('電池容量', batCap, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10))),
              const SizedBox(width: 8),
              Expanded(child: _buildWhiteMetricCard('電池電壓', batV, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10))),
              const SizedBox(width: 8),
              Expanded(child: _buildWhiteMetricCard('電池電流', batI, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildWhiteMetricCard('今日充電量', chargeStr)),
              const SizedBox(width: 10),
              Expanded(child: _buildWhiteMetricCard('今日放電量', dischargeStr)),
            ],
          ),
          const SizedBox(height: 16),
          _buildInteractiveChartContainer('battery', [
            MapEntry(const Color(0xFF0D9488), '電池容量 (%)'),
            MapEntry(const Color(0xFF7C3AED), '電池電流 (A)'),
          ]),
        ],
      ),
    );
  }

  Widget _buildGridTab() {
    String acInVR = _realtimeLatestTest?['ac_in_v_r'] != null ? '${_realtimeLatestTest!['ac_in_v_r']} V' : '--';
    String acInVS = _realtimeLatestTest?['ac_in_v_s'] != null ? '${_realtimeLatestTest!['ac_in_v_s']} V' : '--';
    String acInFreq = _realtimeLatestTest?['ac_in_freq'] != null ? '${_realtimeLatestTest!['ac_in_freq']} Hz' : '--';

    double? acInW = _realtimeLatestInvPs?['ac_in_total_active_power'] != null 
        ? double.tryParse(_realtimeLatestInvPs!['ac_in_total_active_power'].toString()) 
        : null;
    String acInWStr = _formatPower(acInW);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14.0),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildWhiteMetricCard('L1輸入電壓', acInVR),
              _buildWhiteMetricCard('L2輸入電壓', acInVS),
              _buildWhiteMetricCard('市電頻率', acInFreq),
              _buildWhiteMetricCard('輸入功率', acInWStr),
            ],
          ),
          const SizedBox(height: 16),
          // 🎯 更新圖例名稱與新指定的顏色 (淺灰/極淺灰/紅)
          _buildInteractiveChartContainer('grid', [
            MapEntry(const Color(0xFF9E9E9E), 'L1輸入電壓 (V)'),
            MapEntry(const Color(0xFFE0E0E0), 'L2輸入電壓 (V)'),
            MapEntry(const Color(0xFFFF5252), '輸入功率 (W)'),
          ]),
        ],
      ),
    );
  }

  Widget _buildWhiteMetricCard(String title, String value, {EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), 
            blurRadius: 12, 
            offset: const Offset(0, 4)
          )
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(color: Colors.black45, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown, 
            alignment: Alignment.centerLeft, 
            child: Text(value, style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w800))
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveChartContainer(String mode, List<MapEntry<Color, String>> legends, {double? maxY}) {
    return Container(
      width: double.infinity,
      height: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), 
            blurRadius: 12, 
            offset: const Offset(0, 4)
          )
        ]
      ),
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onPanUpdate: (details) { setState(() { _touchPosition = details.localPosition; }); },
              onPanDown: (details) { setState(() { _touchPosition = details.localPosition; }); },
              onPanEnd: (details) { setState(() { _touchPosition = null; }); },
              child: CustomPaint(
                size: Size.infinite,
                painter: DualAxisPowerChartPainter(
                  historyTest: _historyTelemetryList,
                  historyInvPs: _historyInvPsList,
                  chartMode: mode,
                  touchPosition: _touchPosition,
                  maxY: maxY, 
                  tariffMode: _tariffMode,       
                  selectedDate: selectedDate,    
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: legends.map((item) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: item.key, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(item.value, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
                ],
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}