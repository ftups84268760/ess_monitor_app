import 'dart:async';
import 'dart:convert';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:home_widget/home_widget.dart';
import '../../core/constants.dart';
import '../../widgets/chart_painters.dart';
import '../../widgets/weather_renderer.dart'; 
import '../settings_screens.dart';
import '../device_info_settings_screen.dart';
import '../tou_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final String timeString; 
  final String lunarString;
  final String deviceDbId;
  final String customInverterName; 
  final bool isDeviceOnline;
  final String accountType; 
  final String inverterSn;
  final ValueChanged<bool>? onDarkEnvChanged;

  const HomeScreen({
    super.key,
    required this.timeString,
    required this.lunarString,
    required this.deviceDbId,
    required this.customInverterName,
    required this.isDeviceOnline,
    required this.accountType, 
    required this.inverterSn,
    this.onDarkEnvChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  // ==========================================
  // 🎨 功能選單與卡片透明度統一控制區 (0.0 全透明 ~ 1.0 不透明)
  // 調整這裡的數值並按 r (Hot Reload)，全選單卡片會立即同步改變透明度！
  // ==========================================
  static const double _kPanelOpacity = 0.35;        // 右側滑動面板外層大毛玻璃底板 (預設 35%)
  static const double _kCardOpacity = 0.60;         // 選單內所有功能卡片統一透明度 (預設 50%)
  static const double _kCardExpandedOpacity = 0.32; // 可收折卡片(收益/TOU/電池)展開後的內層底色 (預設 32%)
  static const double _kCardBorderOpacity = 0.45;   // 卡片邊緣高光白框透明度 (預設 45%)
  bool? _lastNotifiedDarkEnv;
  
  int? batterySoc;
  double? pvPower;       
  double? gridPower;     
  double? loadPower;     
  double? todaySolar;    
  double? todayLoad;
  double? todayGrid;     

  double? _historicalSolar;
  
  double? get _cumulativeSolar => (_historicalSolar != null || todaySolar != null) 
      ? ((_historicalSolar ?? 0.0) + (todaySolar ?? 0.0)) 
      : null;

  int dcAcPowerDir = 0;
  int linePowerDir = 0;
  int batteryPowerDir = 0;

  Map<String, dynamic>? _touSettings;
  String _lastUpdateTime = '--/--/-- --:--:--';
  String _rawTariffMode = '一般累進表燈(住商)';
  double _customTariffRate = 3.5; 
  bool _isStormBackupMode = false;
  
  List<Map<String, dynamic>> _savingsData = [];
  double _todayTotalSavings = 0.0;

  List<Map<String, dynamic>> _batteries = [];
  bool _isLoadingBatteries = true;

  bool _isFetchingTelemetry = false;
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _hasCheckedFirstTimeSetup = false;
  
  bool _isTouPanelVisible = false;

  bool get _isAllDataNull => pvPower == null && gridPower == null && loadPower == null && batterySoc == null;
  int get _effectiveDcAcDir => (!widget.isDeviceOnline || _isAllDataNull) ? 0 : dcAcPowerDir;
  int get _effectiveLineDir => (!widget.isDeviceOnline || _isAllDataNull) ? 0 : linePowerDir;
  int get _effectiveBatteryDir => (!widget.isDeviceOnline || _isAllDataNull) ? 0 : batteryPowerDir;

  double get _effectiveLoadPower {
    if (!widget.isDeviceOnline) return 0.0;
    if (batterySoc == null && gridPower == null) return 0.0;
    return loadPower ?? 0.0;
  }

  late AnimationController _energyAnimationController;
  Timer? _autoWeatherRefreshTimer;
  Timer? _telemetryTimer; 
  Timer? _savingsTimer; 
  
  RealtimeChannel? _psChannel;
  RealtimeChannel? _testChannel;

  String _locationDisplay = '讀取中...';
  String _weatherDisplay = '';
  
  int _currentWeatherCode = -1;
  bool _isTyphoonWarning = false;

  bool get _isDarkWeather {
    final hour = DateTime.now().hour;
    final bool isNightTime = hour >= 17 || hour < 6;

    final condition = _getWeatherCondition(_currentWeatherCode);
    final bool isDarkWeatherCondition = 
           condition == WeatherCondition.thunderstorm ||
           condition == WeatherCondition.typhoon ||
           condition == WeatherCondition.rainy ||
           condition == WeatherCondition.cloudy ||
           condition == WeatherCondition.snow;

    return isNightTime || isDarkWeatherCondition;
  }

  String _formatPower(double? watts) {
    if (watts == null) return '--';
    if (watts >= 1000) return '${(watts / 1000.0).toStringAsFixed(2)} kW';
    return '${watts.toStringAsFixed(0)} W';
  }

  String _formatTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return '--/--/-- --:--:--';
    try {
      DateTime dt = DateTime.parse(raw).toLocal().subtract(const Duration(hours: 8));
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
             '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (e) {
      return raw; 
    }
  }

  String _getDateHeaderString() {
    final now = DateTime.now();
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} ${weekdays[now.weekday - 1]} (${widget.lunarString})';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _energyAnimationController = AnimationController(
      value: 0.0, vsync: this, duration: const Duration(milliseconds: 2200),
    )..repeat();

    _fetchRealLocationAndWeather();
    _fetchInitialTelemetryData();
    _fetchBatteries(); 
    _setupRealtimeSubscription();
    _fetchTelemetryDataFromSupabase();

    _startTimers();
    _initConnectivityListener();
  }

  void _startTimers() {
    _autoWeatherRefreshTimer?.cancel();
    _telemetryTimer?.cancel();
    _savingsTimer?.cancel();
    
    _autoWeatherRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _fetchRealLocationAndWeather());
    _telemetryTimer = Timer.periodic(const Duration(seconds: 180), (_) => _fetchTelemetryDataFromSupabase());
    _savingsTimer = Timer.periodic(const Duration(minutes: 5), (_) => _fetchSavingsData());
  }

  void _stopTimers() {
    _autoWeatherRefreshTimer?.cancel();
    _telemetryTimer?.cancel();
    _savingsTimer?.cancel();
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      final bool hasNetwork = !result.contains(ConnectivityResult.none);
      if (!hasNetwork && _isOnline) {
        _isOnline = false;
        _stopTimers();
        debugPrint('⚠️ 首頁偵測到斷網，已暫停輪詢計時器');
      } else if (hasNetwork && !_isOnline) {
        _isOnline = true;
        debugPrint('🌐 首頁偵測到網路恢復，重啟輪詢');
        _fetchRealLocationAndWeather();
        _fetchTelemetryDataFromSupabase();
        _startTimers();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 畫面喚醒：重置網路鎖並重啟更新');
      _isFetchingTelemetry = false;
      _startTimers(); 
      
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _fetchRealLocationAndWeather();
          _fetchTelemetryDataFromSupabase();
          _fetchBatteries();
          _setupRealtimeSubscription(); 
        }
      });
      
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      debugPrint('📱 畫面鎖定/背景：暫停更新與中斷殭屍連線');
      _stopTimers();
      _psChannel?.unsubscribe();
      _testChannel?.unsubscribe();
      _psChannel = null;
      _testChannel = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _stopTimers();
    _psChannel?.unsubscribe();
    _testChannel?.unsubscribe();
    _energyAnimationController.dispose();
    super.dispose();
  }

  Future<void> _fetchBatteries() async {
    if (widget.inverterSn.isEmpty) return;
    if (mounted) setState(() => _isLoadingBatteries = true);
    try {
      final batData = await Supabase.instance.client
          .from('device_bat')
          .select('*')
          .eq('device_id', widget.inverterSn) 
          .order('created_at', ascending: true);
          
      if (mounted) {
        setState(() {
          _batteries = List<Map<String, dynamic>>.from(batData);
          _isLoadingBatteries = false;
        });
      }
    } catch(e) {
      debugPrint('首頁讀取電池失敗: $e');
      if (mounted) setState(() => _isLoadingBatteries = false);
    }
  }

  Future<void> _checkAndShowFirstTimeSetup() async {
    if (_hasCheckedFirstTimeSetup || widget.deviceDbId.isEmpty) return;
    
    _hasCheckedFirstTimeSetup = true; 
    
    bool isRootOrOwner = false;
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final data = await Supabase.instance.client
            .from('devices')
            .select('user_id')
            .eq('id', widget.deviceDbId)
            .maybeSingle();
            
        if (data != null) {
          isRootOrOwner = (data['user_id'] == user.id) || 
                          widget.accountType == '系統管理員(root)';
        }
      } catch (_) {}
    }

    if (!isRootOrOwner) return; 

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, 
        builder: (context) => FirstTimeSetupWizard(
          deviceDbId: widget.deviceDbId,
          inverterSn: widget.inverterSn,
          onSetupComplete: () {
            _fetchRealLocationAndWeather(); 
          },
        ),
      );
    }
  }

  Future<void> _fetchRealLocationAndWeather() async {
    try {
      if (widget.deviceDbId.isEmpty) {
        setState(() {
          _locationDisplay = '尚未設定';
          _weatherDisplay = '';
          _currentWeatherCode = -1;
          _isTyphoonWarning = false;
          _rawTariffMode = '一般累進表燈(住商)';
        });
        return;
      }

      final data = await Supabase.instance.client
          .from('devices')
          .select('address, electricity_tariff, tou_settings, is_storm_backup_mode, custom_tariff_rate') 
          .eq('id', widget.deviceDbId)
          .maybeSingle();

      if (data == null) return;

      final String rawAddress = (data['address'] ?? '').toString().trim();
      final String tariffMode = data['electricity_tariff'] ?? '一般累進表燈(住商)';

      if (mounted) {
        setState(() {
          _rawTariffMode = tariffMode; 
          _customTariffRate = double.tryParse((data['custom_tariff_rate'] ?? 3.5).toString()) ?? 3.5;
          _touSettings = data['tou_settings'];
          _isStormBackupMode = data['is_storm_backup_mode'] ?? false;
        });
        _fetchSavingsData();
      }

      if (rawAddress.isEmpty || rawAddress == '尚未設定' || rawAddress == '未設定安裝地址') {
        _checkAndShowFirstTimeSetup();
        
        if (mounted) {
          setState(() {
            _locationDisplay = '尚未設定';
            _weatherDisplay = '';
            _currentWeatherCode = -1;
            _isTyphoonWarning = false;
          });
        }
        return;
      }

      String city = rawAddress;
      String district = '';
      if (rawAddress.length >= 3) {
        city = rawAddress.substring(0, 3);
        district = rawAddress.substring(3);
      }

      String cwaCityName = city.replaceAll('台', '臺');
      final url = 'https://opendata.cwa.gov.tw/api/v1/rest/datastore/F-C0032-001?Authorization=$cwaApiKey&locationName=$cwaCityName';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final jsonResult = jsonDecode(response.body);
        final locationList = jsonResult['records']['location'] as List;

        if (locationList.isNotEmpty) {
          final weatherElements = locationList.first['weatherElement'] as List;
          String wxText = '';
          String minTemp = '25';
          String maxTemp = '32';

          for (var element in weatherElements) {
            String elementName = element['elementName'];
            List timeSeries = element['time'];
            if (timeSeries.isNotEmpty) {
              var firstPeriod = timeSeries.first['parameter'];
              if (elementName == 'Wx') {
                wxText = firstPeriod['parameterName'] ?? '';
              } else if (elementName == 'MinT') {
                minTemp = firstPeriod['parameterName'] ?? '25';
              } else if (elementName == 'MaxT') {
                maxTemp = firstPeriod['parameterName'] ?? '32';
              }
            }
          }

          int calculatedCode = _parseCwaWxToCode(wxText);
          bool currentTyphoonWarning = false;

          try {
            final alertUrl = 'https://opendata.cwa.gov.tw/api/v1/rest/datastore/W-C0033-001?Authorization=$cwaApiKey';
            final alertResponse = await http.get(Uri.parse(alertUrl)).timeout(const Duration(seconds: 4));

            if (alertResponse.statusCode == 200) {
              final alertJson = jsonDecode(alertResponse.body);
              final records = alertJson['records'];
              
              if (records != null && records['hazardConditions'] != null) {
                final hazards = records['hazardConditions']['hazards'] as List?;
                if (hazards != null) {
                  for (var hazard in hazards) {
                    final info = hazard['info'];
                    if (info != null && (info['phenomena'] == '颱風' || info['significance'] == '颱風警報')) {
                      final affectedAreas = info['affectedAreas']['location'] as List?;
                      if (affectedAreas != null) {
                        for (var area in affectedAreas) {
                          if (area['locationName'] == cwaCityName) {
                            currentTyphoonWarning = true;
                            break;
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('⚠️ 警特報 API 讀取失敗: $e');
          }

          if (mounted) {
            setState(() {
              _locationDisplay = '$city$district';
              _weatherDisplay = '$wxText $minTemp~$maxTemp°C';
              _currentWeatherCode = calculatedCode;
              _isTyphoonWarning = currentTyphoonWarning; 
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationDisplay = '尚未設定';
          _weatherDisplay = '';
          _currentWeatherCode = -1;
          _isTyphoonWarning = false;
        });
      }
    }
  }

  Future<void> _fetchSavingsData() async {
    if (widget.deviceDbId.isEmpty) return;
    try {
      final String sn = widget.inverterSn;
      
      final now = DateTime.now();
      final startTime = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T00:00:00.000";
      final endTime = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T23:59:59.999";

      final response = await Supabase.instance.client.rpc('calculate_hourly_solar_savings', params: {'target_device_id': sn, 'tariff_type': _rawTariffMode, 'start_time': startTime, 'end_time': endTime});
      if (mounted && response != null) {
        double total = 0.0;
        List<Map<String, dynamic>> parsedData = [];
        for (var row in (response as List)) {
          double saved = double.tryParse(row['saved_twd'].toString()) ?? 0.0;
          total += saved;
          parsedData.add({'hour': row['hour_of_day'], 'saved': saved, 'period': row['tou_period']});
        }
        parsedData.sort((a, b) => (a['hour'] as int).compareTo(b['hour'] as int));
        setState(() { _savingsData = parsedData; _todayTotalSavings = total; });
      }
    } catch (e) {
      debugPrint('取得收益數據失敗: $e');
    }
  }

  Future<void> _fetchInitialTelemetryData() async {
    try {
      if (widget.deviceDbId.isEmpty) return;
      final String sn = widget.inverterSn;
      if (sn.isEmpty) return;

      final invPsRes = await Supabase.instance.client.from('telemetry_inv_ps')
          .select('solar1_input_power, solar2_input_power, ac_in_total_active_power, ac_out_total_active_power, battery_power_direction, created_at')
          .eq('device_id', sn).order('created_at', ascending: false).limit(1);
          
      final testRes = await Supabase.instance.client.from('telemetry_test')
          .select('battery_capacity, dc_ac_power_direction, line_power_direction, created_at')
          .eq('device_id', sn).order('created_at', ascending: false).limit(1);
          
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      
      final dailyRes = await Supabase.instance.client.from('daily_energy_stats')
          .select('today_solar_kwh, today_load_kwh, today_grid_kwh')
          .eq('device_id', sn).eq('date', dateStr).limit(1);
          
      final histRes = await Supabase.instance.client.from('daily_energy_stats')
          .select('today_solar_kwh')
          .eq('device_id', sn).neq('date', dateStr);

      if (mounted) {
        setState(() {
          if (invPsRes.isNotEmpty) _updatePsData(invPsRes.first);
          if (testRes.isNotEmpty) _updateTestData(testRes.first);
          if (dailyRes.isNotEmpty) {
            final dailyData = dailyRes.first;
            todaySolar = double.tryParse((dailyData['today_solar_kwh'] ?? 0).toString());
            todayLoad = double.tryParse((dailyData['today_load_kwh'] ?? 0).toString());
            todayGrid = double.tryParse((dailyData['today_grid_kwh'] ?? 0).toString());
          }
          double histTotal = 0.0;
          for (var row in histRes) { histTotal += double.tryParse((row['today_solar_kwh'] ?? 0).toString()) ?? 0.0; }
          _historicalSolar = histTotal;
        });
      }
    } catch (e) { debugPrint('Initial Fetch Error: $e'); }
  }

  Future<void> _setupRealtimeSubscription() async {
    if (widget.deviceDbId.isEmpty) return;
    final String sn = widget.inverterSn;
    if (sn.isEmpty) return;

    _psChannel?.unsubscribe();
    _testChannel?.unsubscribe();

    _psChannel = Supabase.instance.client.channel('ps_channel_$sn');
    _psChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert, 
      schema: 'public', 
      table: 'telemetry_inv_ps', 
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'device_id', value: sn), 
      callback: (payload) {
        debugPrint('⚡ 收到推播 (InvPs) ID: ${payload.newRecord['id']}');
        if (mounted) setState(() { _updatePsData(payload.newRecord); });
      }
    ).subscribe((status, [error]) {
      debugPrint('📡 InvPs Realtime 狀態: $status');
      if (error != null) debugPrint('⚠️ InvPs Realtime 錯誤: $error');
    });

    _testChannel = Supabase.instance.client.channel('test_channel_$sn');
    _testChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert, 
      schema: 'public', 
      table: 'telemetry_test', 
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'device_id', value: sn), 
      callback: (payload) {
        debugPrint('⚡ 收到推播 (Test) ID: ${payload.newRecord['id']}');
        if (mounted) setState(() { _updateTestData(payload.newRecord); });
      }
    ).subscribe((status, [error]) {
      debugPrint('📡 Test Realtime 狀態: $status');
      if (error != null) debugPrint('⚠️ Test Realtime 錯誤: $error');
    });
  }

  void _updatePsData(Map<String, dynamic> data) {
    double s1 = double.tryParse((data['solar1_input_power'] ?? 0).toString()) ?? 0.0;
    double s2 = double.tryParse((data['solar2_input_power'] ?? 0).toString()) ?? 0.0;
    pvPower = s1 + s2;
    gridPower = double.tryParse((data['ac_in_total_active_power'] ?? 0).toString());
    loadPower = double.tryParse((data['ac_out_total_active_power'] ?? 0).toString());
    batteryPowerDir = int.tryParse((data['battery_power_direction'] ?? 0).toString()) ?? 0;
    if (data['created_at'] != null) _lastUpdateTime = _formatTimestamp(data['created_at'].toString());
  }

  void _updateTestData(Map<String, dynamic> data) {
    batterySoc = int.tryParse((data['battery_capacity'] ?? 0).toString());
    dcAcPowerDir = int.tryParse((data['dc_ac_power_direction'] ?? 0).toString()) ?? 0;
    linePowerDir = int.tryParse((data['line_power_direction'] ?? 0).toString()) ?? 0;
    if (data['created_at'] != null) _lastUpdateTime = _formatTimestamp(data['created_at'].toString());
    
    if (batterySoc != null) {
      _updateDesktopWidget();
    }
  }

  Future<void> _updateDesktopWidget() async {
    if (kIsWeb) return; 

    if (batterySoc == null) return;
    try {
      await HomeWidget.setAppGroupId('group.com.flighttechnic.ftess');
      
      await HomeWidget.saveWidgetData<int>('battery_soc', batterySoc!);
      await HomeWidget.saveWidgetData<String>('device_name', widget.customInverterName);
      
      bool isCharging = batteryPowerDir == 1;
      await HomeWidget.saveWidgetData<bool>('is_charging', isCharging);
      
      await HomeWidget.updateWidget(
        iOSName: 'EssBatteryWidget', 
        androidName: 'EssBatteryWidgetProvider'
      );
    } catch (e) {
      debugPrint('更新 Widget 失敗: $e');
    }
  }

  Future<void> _fetchTelemetryDataFromSupabase() async {
    if (_isFetchingTelemetry) return; 
    _isFetchingTelemetry = true;

    try {
      if (widget.deviceDbId.isEmpty) return;
      final devRes = await Supabase.instance.client.from('devices').select('is_storm_backup_mode').eq('id', widget.deviceDbId).maybeSingle();
      if (devRes == null) return;
      final String sn = widget.inverterSn;
      if (sn.isEmpty) return;
      
      final invPsRes = await Supabase.instance.client.from('telemetry_inv_ps')
          .select('solar1_input_power, solar2_input_power, ac_in_total_active_power, ac_out_total_active_power, battery_power_direction, created_at')
          .eq('device_id', sn).order('created_at', ascending: false).limit(1);
          
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      
      final dailyRes = await Supabase.instance.client.from('daily_energy_stats')
          .select('today_solar_kwh, today_load_kwh, today_grid_kwh')
          .eq('device_id', sn).eq('date', dateStr).limit(1);
          
      final testRes = await Supabase.instance.client.from('telemetry_test')
          .select('battery_capacity, dc_ac_power_direction, line_power_direction, created_at')
          .eq('device_id', sn).order('created_at', ascending: false).limit(1);

      if (mounted) {
        setState(() {
          _isStormBackupMode = devRes['is_storm_backup_mode'] ?? false;
          if (invPsRes.isNotEmpty) {
            final psData = invPsRes.first; 
            double s1 = double.tryParse((psData['solar1_input_power'] ?? 0).toString()) ?? 0.0;
            double s2 = double.tryParse((psData['solar2_input_power'] ?? 0).toString()) ?? 0.0;
            pvPower = s1 + s2;
            gridPower = double.tryParse((psData['ac_in_total_active_power'] ?? 0).toString());
            loadPower = double.tryParse((psData['ac_out_total_active_power'] ?? 0).toString());
            batteryPowerDir = int.tryParse((psData['battery_power_direction'] ?? 0).toString()) ?? 0;
            if (psData['created_at'] != null) _lastUpdateTime = _formatTimestamp(psData['created_at'].toString());
          } else { pvPower = null; gridPower = null; loadPower = null; }

          if (dailyRes.isNotEmpty) {
            final dailyData = dailyRes.first;
            todaySolar = double.tryParse((dailyData['today_solar_kwh'] ?? 0).toString());
            todayLoad = double.tryParse((dailyData['today_load_kwh'] ?? 0).toString());
            todayGrid = double.tryParse((dailyData['today_grid_kwh'] ?? 0).toString());
          } else { todaySolar = null; todayLoad = null; }

          if (testRes.isNotEmpty) {
            final testData = testRes.first;
            batterySoc = int.tryParse((testData['battery_capacity'] ?? 0).toString());
            dcAcPowerDir = int.tryParse((testData['dc_ac_power_direction'] ?? 0).toString()) ?? 0;
            linePowerDir = int.tryParse((testData['line_power_direction'] ?? 0).toString()) ?? 0;
            if (invPsRes.isEmpty && testData['created_at'] != null) _lastUpdateTime = _formatTimestamp(testData['created_at'].toString());
            
            if (batterySoc != null) {
              _updateDesktopWidget();
            }
          } else { batterySoc = null; }
        });
      }
    } catch (e) {
      if (mounted) setState(() { pvPower = null; gridPower = null; loadPower = null; todaySolar = null; todayLoad = null; batterySoc = null; });
    } finally {
      _isFetchingTelemetry = false;
    }
  }

  Future<void> _restoreTouMode() async {
    if (widget.deviceDbId.isEmpty) return;
    try {
      final String sn = widget.inverterSn;
      final settings = _touSettings ?? {};
      final bool isSeason = settings['isSeasonModeEnabled'] ?? false;
      final int startM = settings['summerStartMonth'] ?? 6;
      final int endM = settings['summerEndMonth'] ?? 9;
      final now = DateTime.now();
      final bool inSummer = isSeason && (now.month >= startM && now.month <= endM);
      final slot0 = inSummer ? (settings['summerSlot0'] ?? {}) : (settings['winterSlot0'] ?? {});
      final slot1 = inSummer ? (settings['summerSlot1'] ?? {}) : (settings['winterSlot1'] ?? {});
      final int dstA = isSeason ? 1 : 0;
      final String bb = startM.toString().padLeft(2, '0');
      final String cc = endM.toString().padLeft(2, '0');
      final int c0 = slot0['state'] ?? 0;
      final String start0 = (slot0['start'] ?? '00:00').replaceAll(':', '');
      final String end0 = (slot0['end'] ?? '00:00').replaceAll(':', '');
      final int c1 = slot1['state'] ?? 0;
      final String start1 = (slot1['start'] ?? '00:00').replaceAll(':', '');
      final String end1 = (slot1['end'] ?? '00:00').replaceAll(':', '');

      List<String> commandsToDeploy = [
        '^S011DST$dstA,$bb,$cc\r',
        '^S019TOU$dstA,0,$c0,$start0,$end0\r',
        '^S019TOU$dstA,1,$c1,$start1,$end1\r'
      ];
      final response = await Supabase.instance.client.functions.invoke('send-device-command', body: {'sn': sn, 'commands': commandsToDeploy});
      if (response.status != 200) throw Exception('雲端派發給設備失敗');
      await Supabase.instance.client.from('devices').update({'is_storm_backup_mode': false}).eq('id', widget.deviceDbId);
      if (mounted) {
        setState(() { _isStormBackupMode = false; });
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已關閉「惡劣天氣備援模式」'), backgroundColor: Colors.teal));
      }
    } catch (e) {
      debugPrint('解除備援模式失敗: $e'); 
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars(); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('系統連線異常，請檢查網路狀態後再試。'), 
          backgroundColor: Colors.redAccent
        ));
      }
    }
  }

  Map<String, String> _getCurrentTariffDetails(String mode) {
    final now = DateTime.now();
    final month = now.month;
    final weekday = now.weekday;
    final hour = now.hour;

    final bool isSummer = (month >= 6 && month <= 9);
    final String season = isSummer ? '夏月' : '非夏月';
    String period = '離峰時段';
    String rate = '--';

    if (mode == '簡易型(二段式)') {
      if (isSummer) {
        if (weekday >= 1 && weekday <= 5 && hour >= 9) { period = '尖峰時段'; rate = '5.16'; }
        else { period = '離峰時段'; rate = '2.06'; }
      } else {
        if (weekday >= 1 && weekday <= 5 && ((hour >= 6 && hour < 11) || (hour >= 14))) { period = '尖峰時段'; rate = '4.93'; }
        else { period = '離峰時段'; rate = '1.99'; }
      }
    } else if (mode == '簡易型(三段式)') {
      if (isSummer) {
        if (weekday >= 1 && weekday <= 5) {
          if (hour >= 16) { period = '尖峰時段'; rate = '7.13'; }
          else if (hour >= 9) { period = '半尖峰時段'; rate = '4.69'; }
          else { period = '離峰時段'; rate = '2.06'; }
        } else { period = '離峰時段'; rate = '2.06'; }
      } else {
        if (weekday >= 1 && weekday <= 5) {
          if ((hour >= 6 && hour < 11) || (hour >= 14)) { period = '半尖峰時段'; rate = '4.48'; }
          else { period = '離峰時段'; rate = '1.99'; }
        } else { period = '離峰時段'; rate = '1.99'; }
      }
    } else if (mode == '標準型(二段式)') {
      if (isSummer) {
        if (weekday >= 1 && weekday <= 5 && hour >= 9) { period = '尖峰時段'; rate = '5.54'; }
        else if (weekday == 6 && hour >= 9) { period = '半尖峰時段'; rate = '2.76'; }
        else { period = '離峰時段'; rate = '2.27'; }
      } else {
        if (weekday >= 1 && weekday <= 5 && ((hour >= 6 && hour < 11) || (hour >= 14))) { period = '尖峰時段'; rate = '5.39'; }
        else if (weekday == 6 && ((hour >= 6 && hour < 11) || (hour >= 14))) { period = '半尖峰時段'; rate = '2.65'; }
        else { period = '離峰時段'; rate = '2.15'; }
      }
    } else if (mode == '標準型(三段式)') {
      if (isSummer) {
        if (weekday >= 1 && weekday <= 5) {
          if (hour >= 16) { period = '尖峰時段'; rate = '8.12'; }
          else if (hour >= 9) { period = '半尖峰時段'; rate = '5.02'; }
          else { period = '離峰時段'; rate = '2.23'; }
        } else if (weekday == 6 && hour >= 9) { period = '半尖峰時段'; rate = '2.50'; }
        else { period = '離峰時段'; rate = '2.23'; }
      } else {
        if (weekday >= 1 && weekday <= 5) {
          if ((hour >= 6 && hour < 11) || (hour >= 14)) { period = '半尖峰時段'; rate = '4.86'; }
          else { period = '離峰時段'; rate = '2.12'; }
        } else if (weekday == 6) {
          if ((hour >= 6 && hour < 11) || (hour >= 14)) { period = '半尖峰時段'; rate = '2.40'; }
          else { period = '離峰時段'; rate = '2.12'; }
        } else { period = '離峰時段'; rate = '2.12'; }
      }
    } else {
      period = '無區分';
      rate = _customTariffRate.toStringAsFixed(2);
    }

    return {'season': season, 'period': period, 'rate': rate};
  }

  int _parseCwaWxToCode(String wx) {
    if (wx.contains('颱風') || wx.contains('暴風') || wx.contains('狂風')) return 99; 
    if (wx.contains('雪') || wx.contains('冰雹')) return 23; 
    if (wx.contains('雷')) return 95;
    if (wx.contains('雨') || wx.contains('陣雨')) return 80;
    if (wx.contains('雲') || wx.contains('陰')) return 2;
    return 0; 
  }

  WeatherCondition _getWeatherCondition(int code) {
    if (_isTyphoonWarning) return WeatherCondition.typhoon; 

    if (code < 0) return WeatherCondition.sunny; 
    if (code == 0) return WeatherCondition.sunny; 
    if (code >= 1 && code <= 3) return WeatherCondition.partlyCloudy; 
    if (code >= 4 && code <= 7) return WeatherCondition.cloudy; 
    if (code == 23 || code == 37 || code == 42) return WeatherCondition.snow; 
    if (code >= 95 && code < 99) return WeatherCondition.thunderstorm; 
    if (code == 99) return WeatherCondition.typhoon; 
    if ((code >= 51 && code <= 65) || (code >= 80 && code <= 82)) return WeatherCondition.rainy;
    return WeatherCondition.sunny;
  }

  // 🎯 輔助方法：檢查管理員或擁有者權限並開啟「電價方案 / 設備資訊設定」頁面
  // 🎯 1. 專供點擊「安裝區域」卡片使用：開啟「設備資訊 (DeviceInfoSettingsScreen)」
  Future<void> _openDeviceInfoPage() async {
    bool isRootOrOwner = false;
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final data = await Supabase.instance.client
            .from('devices')
            .select('user_id')
            .eq('id', widget.deviceDbId)
            .maybeSingle();
        if (data != null) {
          isRootOrOwner = (data['user_id'] == user.id) ||
              widget.accountType == '系統管理員(root)';
        }
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceInfoSettingsScreen(
          deviceDbId: widget.deviceDbId,
          isRootOrOwner: isRootOrOwner,
          accountType: widget.accountType,
        ),
      ),
    );
    _fetchRealLocationAndWeather();
  }

  // 🎯 2. 專供點擊「計價模式」使用：直接開啟「電價方案 (ElectricityTariffScreen)」頁面
  Future<void> _openTariffSettingsPage() async {
    bool isRootOrOwner = false;
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final data = await Supabase.instance.client
            .from('devices')
            .select('user_id')
            .eq('id', widget.deviceDbId)
            .maybeSingle();
        if (data != null) {
          isRootOrOwner = (data['user_id'] == user.id) ||
              widget.accountType == '系統管理員(root)';
        }
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ElectricityTariffScreen(
          deviceDbId: widget.deviceDbId,
          isRootOrOwner: isRootOrOwner,
        ),
      ),
    );
    _fetchRealLocationAndWeather();
  }

  Widget _buildTariffContent(Map<String, String> details, double maxSaved) {
    final Color seasonColor = details['season'] == '夏月' ? Colors.orange : Colors.blueAccent;
    Color periodColor = Colors.teal;
    if (details['period'] == '尖峰時段') {
      periodColor = Colors.redAccent;
    } else if (details['period'] == '半尖峰時段') {
      periodColor = Colors.orange;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🎯 點擊「計價模式」直接開啟 ElectricityTariffScreen (電價方案頁面)
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _openTariffSettingsPage,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('計價模式', style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_rawTariffMode, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: Colors.teal),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('當前狀態', style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: seasonColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(details['season']!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: seasonColor)),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: periodColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text('${details['period']} (${details['rate']} 元)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: periodColor)),
                ),
              ],
            )
          ],
        ),
        const SizedBox(height: 12),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('今日各時段收益 (NT\$)', style: TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.bold)),
            Text('總計: \$ ${_todayTotalSavings.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: _savingsData.isEmpty
              ? const Center(child: Text('尚無今日收益數據', style: TextStyle(fontSize: 11, color: Colors.black26)))
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _savingsData.length,
                  itemBuilder: (context, index) {
                    final item = _savingsData[index];
                    final String period = item['period'];
                    final double saved = item['saved'];
                    final int hour = item['hour'];
                    
                    Color barColor = Colors.teal.shade300;
                    if (period == '尖峰') barColor = Colors.redAccent.shade200;
                    if (period == '半尖峰') barColor = Colors.orangeAccent;

                    double barHeight = (saved / maxSaved) * 45.0;
                    if (barHeight < 2 && saved > 0) barHeight = 2;

                    return Container(
                      width: 30,
                      margin: const EdgeInsets.only(right: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(saved > 0 ? saved.toStringAsFixed(1) : '', style: const TextStyle(fontSize: 9, color: Colors.black54)),
                          const SizedBox(height: 2),
                          Container(
                            width: 14,
                            height: barHeight,
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(hour.toString().padLeft(2, '0'), style: const TextStyle(fontSize: 9, color: Colors.black38)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // 🎯 單行緊湊版「今日預估發電收益」卡片 (綁定 _kCardOpacity)
  Widget _buildTariffCard() {
    final details = _getCurrentTariffDetails(_rawTariffMode);
    double maxSaved = 0;
    for (var item in _savingsData) {
      if (item['saved'] > maxSaved) maxSaved = item['saved'];
    }
    if (maxSaved == 0) maxSaved = 1; 

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _kCardOpacity),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: _kCardBorderOpacity)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          iconColor: Colors.teal,
          collapsedIconColor: Colors.black38,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          leading: const Icon(Icons.price_change_outlined, color: Colors.teal, size: 16),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('今日預估發電收益', style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600)),
              Text(
                'NT\$ ${_todayTotalSavings.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal),
              ),
            ],
          ),
          children: [
            const Divider(height: 1, color: Colors.black12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: _kCardExpandedOpacity),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
              ),
              child: _buildTariffContent(details, maxSaved),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTouSettingsContent(BuildContext context, bool isEffectivelyBackup, bool isSeason, int startM, int endM) {
    Widget buildSlot(String title, Map<String, dynamic>? slot) {
      if (slot == null) return const SizedBox.shrink();
      int state = slot['state'] ?? 0;
      String start = slot['start'] ?? '00:00';
      String end = slot['end'] ?? '00:00';
      
      String stateStr = state == 0 ? '關閉' : (state == 1 ? '充電' : '放電');
      Color stateColor = state == 0 ? Colors.black38 : (state == 1 ? Colors.teal : Colors.orange);

      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: stateColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(stateStr, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: stateColor)),
            ),
            const SizedBox(width: 8),
            Text('$start - $end', style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          bool isRootOrOwner = false;
          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            try {
              final data = await Supabase.instance.client
                  .from('devices')
                  .select('user_id')
                  .eq('id', widget.deviceDbId)
                  .maybeSingle();
                  
              if (data != null) {
                isRootOrOwner = (data['user_id'] == user.id) || 
                                widget.accountType == '系統管理員(root)';
              }
            } catch (_) {}
          }

          if (!context.mounted) return;
          
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TouSettingsScreen(
                deviceDbId: widget.deviceDbId,
                isRootOrOwner: isRootOrOwner,
              ),
            ),
          );
          
          _fetchRealLocationAndWeather();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isEffectivelyBackup) ...[
              Text(
                _isStormBackupMode ? '惡劣天氣備援模式' : '全天候備援模式', 
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade700)
              ),
              buildSlot('時段 1', {'state': 1, 'start': '00:00', 'end': '00:00'}),
              buildSlot('時段 2', {'state': 1, 'start': '00:00', 'end': '00:00'}),
            ] else if (isSeason) ...[
              Text('夏月排程 ($startM月~$endM月)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
              buildSlot('時段 1', _touSettings!['summerSlot0']),
              buildSlot('時段 2', _touSettings!['summerSlot1']),
              const SizedBox(height: 8),
              const Text('非夏月排程', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
              buildSlot('時段 1', _touSettings!['winterSlot0']),
              buildSlot('時段 2', _touSettings!['winterSlot1']),
            ] else ...[
              const Text('全年排程', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal)),
              buildSlot('時段 1', _touSettings!['winterSlot0']),
              buildSlot('時段 2', _touSettings!['winterSlot1']),
            ]
          ],
        ),
      ),
    );
  }

  // 🎯 單行緊湊版「時間電價(TOU)排程」卡片 (綁定 _kCardOpacity)
  Widget _buildTouSettingsCard() {
    if (_touSettings == null && !_isStormBackupMode) return const SizedBox.shrink();

    final bool isSeason = _touSettings?['isSeasonModeEnabled'] ?? false;
    final int startM = _touSettings?['summerStartMonth'] ?? 6;
    final int endM = _touSettings?['summerEndMonth'] ?? 9;

    bool isManualBackup = false;
    if (_touSettings != null && !isSeason) {
      final slot0 = _touSettings!['winterSlot0'];
      final slot1 = _touSettings!['winterSlot1'];
      if (slot0 != null && slot1 != null &&
          slot0['state'] == 1 && slot0['start'] == '00:00' && slot0['end'] == '00:00' &&
          slot1['state'] == 1 && slot1['start'] == '00:00' && slot1['end'] == '00:00') {
        isManualBackup = true;
      }
    }

    final bool isEffectivelyBackup = _isStormBackupMode || isManualBackup;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _kCardOpacity), 
        borderRadius: BorderRadius.circular(10), 
        border: Border.all(color: Colors.white.withValues(alpha: _kCardBorderOpacity)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          iconColor: Colors.teal,
          collapsedIconColor: Colors.black38,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          leading: const Icon(Icons.schedule_rounded, color: Colors.teal, size: 16),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('時間電價(TOU)', style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600)),
              Text(
                isEffectivelyBackup 
                    ? '一般運行' 
                    : (isSeason ? '夏月/非夏月' : '全年共用'), 
                style: TextStyle(
                  fontSize: 11, 
                  fontWeight: FontWeight.bold, 
                  color: isEffectivelyBackup ? Colors.orange.shade700 : Colors.teal,
                ),
              ),
            ],
          ),
          children: [
            const Divider(height: 1, color: Colors.black12),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: _kCardExpandedOpacity),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: _buildTouSettingsContent(context, isEffectivelyBackup, isSeason, startM, endM),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎯 「安裝區域」圓角卡片 (綁定 _kCardOpacity)
  Widget _buildWebLocationCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _kCardOpacity),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: _kCardBorderOpacity)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _openDeviceInfoPage,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on_rounded, color: (_locationDisplay == '尚未設定') ? Colors.orangeAccent : Colors.teal, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _locationDisplay == '尚未設定' ? '設定地址' : _locationDisplay,
                      style: TextStyle(fontSize: 11, color: (_locationDisplay == '尚未設定') ? Colors.orange.shade700 : Colors.black87, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🎯 「天氣狀態」圓角卡片 (綁定 _kCardOpacity)
  Widget _buildWebWeatherCard() {
    if (_weatherDisplay.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _kCardOpacity),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: _kCardBorderOpacity)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_isTyphoonWarning ? Icons.cyclone_rounded : Icons.cloud_queue_rounded, color: _isTyphoonWarning ? Colors.redAccent : Colors.blueAccent, size: 14),
          const SizedBox(width: 4),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _weatherDisplay,
                style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🎯 網頁版專用：「電池模組列表」卡片 (綁定 _kCardOpacity)
  Widget _buildBatteryExpansionCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _kCardOpacity),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: _kCardBorderOpacity)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          iconColor: Colors.teal,
          collapsedIconColor: Colors.black38,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          leading: const Icon(Icons.battery_charging_full_rounded, color: Colors.teal, size: 16),
          title: const Text('電池模組列表', style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600)),
          children: [
            const Divider(height: 1, color: Colors.black12),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: _kCardExpandedOpacity),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
              ),
              child: _buildSidebarBatteryList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarBatteryList() {
    if (_isLoadingBatteries) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: Colors.teal)));
    }
    if (_batteries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: _kCardExpandedOpacity), borderRadius: BorderRadius.circular(10)),
        child: const Center(child: Text('目前尚未綁定任何電池模組', style: TextStyle(color: Colors.black38, fontSize: 11)))
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _kCardExpandedOpacity),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _batteries.length,
        separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.black12),
        itemBuilder: (context, index) {
          final bat = _batteries[index];
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(6), 
                border: Border.all(color: Colors.black12), 
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset('assets/images/bat_icon.png', fit: BoxFit.contain),
              ),
            ),
            title: const Text('FT-IFS-B05', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            subtitle: Text('SN: ${bat['bat_sn']}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
          );
        },
      ),
    );
  }

  Widget _buildStormBackupBanner() {
    if (!_isStormBackupMode) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200, width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('惡劣天氣備援執行中', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                Text('已暫停 TOU 排程並維持高儲備電量', style: TextStyle(color: Colors.red.shade700, fontSize: 10)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              minimumSize: const Size(0, 28),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 0,
            ),
            onPressed: () {
              // 🎯 統一改為：背景模糊 (sigma: 10) + 黑色半透明視窗 (alpha: 0.6)
              showDialog(
                context: context,
                builder: (BuildContext dialogContext) {
                  return BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: AlertDialog(
                      backgroundColor: Colors.black.withValues(alpha: 0.6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      title: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.tealAccent, size: 22),
                          SizedBox(width: 8),
                          Text(
                            '解除備援模式',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      content: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: const Text(
                          '確定要解除「惡劣天氣備援模式」嗎？',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(), 
                          child: const Text('取消', style: TextStyle(color: Colors.grey)),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop(); 
                            _restoreTouMode();           
                          },
                          child: const Text(
                            '確定解除',
                            style: TextStyle(
                              color: Colors.tealAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            child: const Text('解除', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 🎯 緊湊化手機數據卡片 + 僅在「手機窄版 (!context.isMobileWideLayout)」顯示底部的設定按鈕
  // (因為「手機寬版」的「設定」已移至左側毛玻璃導覽列「設備列表」的下方！)
  Widget _buildMobileExtraStatsAndSettings() {
    final bool isMobileWide = context.isMobileWideLayout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: _buildHalfMenuCard('今日發電', todaySolar != null ? '${todaySolar!.toStringAsFixed(2)} kWh' : '--', icon: Icons.solar_power_rounded)),
            const SizedBox(width: 6),
            Expanded(child: _buildHalfMenuCard('今日用電', todayLoad != null ? '${todayLoad!.toStringAsFixed(2)} kWh' : '--', icon: Icons.home_rounded)),
          ],
        ),
        const SizedBox(height: 6),
        
        Builder(
          builder: (context) {
            if (_cumulativeSolar == null || _cumulativeSolar == 0.0) {
              return Row(
                children: [
                  Expanded(child: _buildHalfMenuCard('累積減碳', '--', icon: Icons.co2_rounded)),
                  const SizedBox(width: 6),
                  Expanded(child: _buildHalfMenuCard('累積植樹', '--', icon: Icons.park_rounded)),
                ],
              );
            }
            
            double carbonReduction = _cumulativeSolar! * 0.495;
            double treeEquivalent = carbonReduction / 12.0;

            String carbonStr;
            if (carbonReduction >= 1000) {
              carbonStr = '${(carbonReduction / 1000).toStringAsFixed(1)} t';
            } else {
              carbonStr = '${carbonReduction.toStringAsFixed(1)} kg';
            }

            return Row(
              children: [
                Expanded(child: _buildHalfMenuCard('累積減碳', carbonStr, icon: Icons.co2_rounded)),
                const SizedBox(width: 6),
                Expanded(child: _buildHalfMenuCard('累積植樹', '${treeEquivalent.toStringAsFixed(1)} 棵', valueColor: Colors.green.shade600, icon: Icons.park_rounded)),
              ],
            );
          }
        ),
        const SizedBox(height: 6),

        Row(
          children: [
            Expanded(child: _buildSelfConsumptionBarCard()),
            const SizedBox(width: 6),
            Expanded(child: _buildSocBarCard()),
          ],
        ),

        // 🎯 關鍵優化：在「手機寬版 (isMobileWide)」下隱藏右側面板底部的「設定」，
        // 改由左側導覽列「設備列表」下方的「設定」子項目統一開啟！
        if (!isMobileWide) ...[
          const SizedBox(height: 8),
          const Divider(color: Colors.black12, height: 1),
          const SizedBox(height: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    settings: const RouteSettings(name: 'device_settings'),
                    builder: (context) => SettingsSubMenuScreen(
                      deviceDbId: widget.deviceDbId,
                      accountType: widget.accountType,
                      inverterSn: widget.inverterSn, 
                    ),
                  ),
                );
                _fetchRealLocationAndWeather();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.teal,
                      radius: 15,
                      child: Icon(Icons.settings_suggest_rounded, color: Colors.white, size: 16),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Colors.black38),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const double figmaWidth = 2063.0;
    const double figmaHeight = 1344.0;
    const double figmaRatio = figmaWidth / figmaHeight;
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    
    final bool isWideScreen = context.useWideLayout;
    final bool isMobileWide = context.isMobileWideLayout;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ─── 🛡️ 第 1 層防護罩：獨立的背景天氣層 ───
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 1200),
                switchInCurve: Curves.easeInOutCubic,
                switchOutCurve: Curves.easeInOutCubic,
                child: RealisticWeatherBg(
                  key: ValueKey(_currentWeatherCode), 
                  condition: _getWeatherCondition(_currentWeatherCode),
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          
          // ─── 🛡️ 第 2 層防護罩：前方數據與 3D 建築主視覺層 ───
          Positioned.fill(
            top: kToolbarHeight + statusBarHeight - 12.0,
            bottom: isWideScreen ? 24.0 : MediaQuery.of(context).size.height * 0.33,
            child: RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 0.0),
                child: Column(
                  children: [
                    Builder(
                      builder: (context) {
                        final bool isDarkEnv = _isDarkWeather;
                        // 🎯 當夜晚或深色天氣狀態改變時，自動通知外層 InnerDashboardNavigation 將逆變器名稱切換為白色！
                        if (_lastNotifiedDarkEnv != isDarkEnv) {
                          _lastNotifiedDarkEnv = isDarkEnv;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              widget.onDarkEnvChanged?.call(isDarkEnv);
                            }
                          });
                        }

                        final Color subTextColor = isDarkEnv ? Colors.white70 : Colors.black87;
                        final Color highlightColor = isDarkEnv ? Colors.orangeAccent : Colors.teal.shade800;

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start, 
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [                         
                                Text(
                                  _getDateHeaderString(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 10, color: subTextColor, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '最後更新: $_lastUpdateTime',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 9, color: highlightColor, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    AnimatedBuilder(
                      animation: _energyAnimationController,
                      builder: (context, child) {
                        return Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              double containerWidth = constraints.maxWidth;
                              double containerHeight = constraints.maxHeight;
                              double containerRatio = containerWidth / containerHeight;
                              double finalWidth, finalHeight;
                              if (containerRatio > figmaRatio) { finalHeight = containerHeight; finalWidth = finalHeight * figmaRatio; } 
                              else { finalWidth = containerWidth; finalHeight = finalWidth / figmaRatio; }
                              double getX(double figmaX) => (figmaX / figmaWidth) * finalWidth;
                              double getY(double figmaY) => (figmaY / figmaHeight) * finalHeight;

                              return Center(
                                child: SizedBox(
                                  width: finalWidth,
                                  height: finalHeight,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned(
                                        left: finalWidth * 0.1,
                                        right: finalWidth * 0.1,
                                        bottom: finalHeight * 0.02, 
                                        height: finalHeight * 0.15,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.all(Radius.elliptical(finalWidth * 0.8, finalHeight * 0.15)),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.35),
                                                blurRadius: 45, 
                                                spreadRadius: 2,
                                                offset: const Offset(0, 25), 
                                              )
                                            ],
                                          ),
                                        ),
                                      ),
                                      Positioned.fill(child: Image.asset('assets/images/energy_base_map.png', fit: BoxFit.fill)),
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: EnergyFlowPainter(
                                            progress: _energyAnimationController.value,
                                            dcAcPowerDirection: _effectiveDcAcDir, 
                                            linePowerDirection: _effectiveLineDir,   
                                            batteryPowerDirection: _effectiveBatteryDir, 
                                            loadPower: _effectiveLoadPower, 
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: getX(218) + (21.0 / figmaWidth) * finalWidth, 
                                        top: getY(-30),
                                        child: buildFixedDashboardItem(title: '電網', value: _formatPower(gridPower)),
                                      ),
                                      Positioned(
                                        left: getX(1457) + (21.0 / figmaWidth) * finalWidth, 
                                        top: getY(-30),
                                        child: buildFixedDashboardItem(title: '太陽能', value: _formatPower(pvPower)),
                                      ),
                                      Positioned(
                                        left: getX(575) + (21.0 / figmaWidth) * finalWidth, 
                                        top: getY(1189),
                                        child: _buildBatteryPill(), 
                                      ),
                                      Positioned(
                                        left: getX(1457) + (21.0 / figmaWidth) * finalWidth, 
                                        top: getY(1189),
                                        child: buildFixedDashboardItem(title: '負載', value: _formatPower(loadPower)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // ─── 🛡️ 第 3 層防護罩：右側水平滑動資訊面板 (網頁版 & 手機寬版共用，綁定 _kPanelOpacity) ───
          if (isWideScreen)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              top: 0,
              bottom: 0,
              right: _isTouPanelVisible ? 0 : -300, 
              child: RepaintBoundary(
                child: Center( 
                  child: Row(
                    mainAxisSize: MainAxisSize.min, 
                    crossAxisAlignment: CrossAxisAlignment.center, 
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isTouPanelVisible = !_isTouPanelVisible;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: _kCardOpacity),
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                            border: Border.all(color: Colors.white.withValues(alpha: _kCardBorderOpacity)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(-2, 2))
                            ]
                          ),
                          child: Icon(
                            _isTouPanelVisible ? Icons.arrow_forward_ios_rounded : Icons.analytics_rounded, 
                            color: Colors.teal, 
                            size: 20
                          ),
                        ),
                      ),
                      
                      SizedBox(
                        width: 300, 
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: Container(
                              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: _kPanelOpacity),
                                borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                                border: Border.all(color: Colors.white.withValues(alpha: _kCardBorderOpacity)),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                                ]
                              ),
                              child: MediaQuery.removePadding(
                                context: context,
                                removeRight: true,
                                removeLeft: true,
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isMobileWide) ...[
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              '系統資訊',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () => setState(() => _isTouPanelVisible = false),
                                              child: const Icon(
                                                Icons.close_rounded,
                                                size: 18,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                      ],

                                      if (isMobileWide) _buildStormBackupBanner(),

                                      Row(
                                        children: [
                                          Expanded(child: _buildWebLocationCard()),
                                          if (_weatherDisplay.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            Expanded(child: _buildWebWeatherCard()),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 6),

                                      _buildTariffCard(),
                                      _buildTouSettingsCard(),
                                      
                                      if (!isMobileWide) _buildBatteryExpansionCard(),

                                      if (isMobileWide) _buildMobileExtraStatsAndSettings(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // ─── 🛡️ 第 4 層防護罩：底部滑動選單 (手機一般窄版專用) ───
          if (!isWideScreen)
            Positioned.fill(
              child: RepaintBoundary(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.33,
                  minChildSize: 0.33, 
                  maxChildSize: 0.75,
                  snap: true,         
                  builder: (BuildContext context, ScrollController scrollController) {
                    return ClipRRect(
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(
                          color: Colors.teal.withValues(alpha: 0.08),
                          child: MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            removeLeft: true,
                            removeRight: true,
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              children: [
                                Center(child: Container(width: 40, height: 4.5, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)))),
                                const SizedBox(height: 14),
                                
                                _buildStormBackupBanner(),

                                Row(
                                  children: [
                                    Expanded(child: _buildWebLocationCard()),
                                    if (_weatherDisplay.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Expanded(child: _buildWebWeatherCard()),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),

                                _buildTariffCard(),
                                _buildTouSettingsCard(),
                                
                                _buildMobileExtraStatsAndSettings(),
                                const SizedBox(height: 30),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildFixedDashboardItem({required String title, required String value}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35), 
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 0.5), 
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))
            ]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatteryPill() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 0.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))
            ]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('電池', style: TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDynamicBatteryIcon(batterySoc),
                  const SizedBox(width: 4),
                  Text(
                    batterySoc != null ? '$batterySoc%' : '--', 
                    style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.2)
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicBatteryIcon(int? soc) {
    if (soc == null) {
      return const Icon(Icons.battery_unknown_rounded, color: Colors.black45, size: 18);
    }
    
    Color batteryColor = Colors.teal;
    if (soc <= 20) {
      batteryColor = Colors.redAccent;
    } else if (soc <= 50) {
      batteryColor = Colors.orangeAccent;
    }

    bool isCharging = batteryPowerDir == 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 24,
          height: 12,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black54, width: 1.2),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 19.0 * (soc / 100.0), 
                  decoration: BoxDecoration(
                    color: batteryColor,
                    borderRadius: BorderRadius.circular(1.0),
                  ),
                ),
              ),
              if (isCharging)
                const Center(
                  child: Icon(Icons.bolt_rounded, size: 10, color: Colors.white),
                ),
            ],
          ),
        ),
        Container(
          width: 2.5,
          height: 5,
          decoration: const BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.horizontal(right: Radius.circular(2)),
          ),
        ),
      ],
    );
  }

  // 🎯 緊湊版四宮格數據卡 (綁定 _kCardOpacity)
  Widget _buildHalfMenuCard(String title, String value, {Color valueColor = Colors.teal, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _kCardOpacity),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: _kCardBorderOpacity)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: Colors.teal),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
          ),
        ],
      ),
    );
  }

  // 🎯 緊湊版「自我供電」進度條卡 (綁定 _kCardOpacity)
  Widget _buildSelfConsumptionBarCard() {
    double load = todayLoad ?? 0.0;
    double grid = todayGrid ?? 0.0;
    double ratio = 0.0;
    if (load > 0) ratio = ((1 - (grid / load)) * 100).clamp(0.0, 100.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _kCardOpacity),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: _kCardBorderOpacity)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('自我供電', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500)),
              Text('${ratio.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: load > 0 ? ratio / 100 : 0.0,
              minHeight: 6,
              backgroundColor: Colors.black12,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
            ),
          ),
        ],
      ),
    );
  }

  // 🎯 緊湊版「電池電量」進度條卡 (綁定 _kCardOpacity)
  Widget _buildSocBarCard() {
    double ratio = (batterySoc ?? 0).toDouble();
    
    Color barColor = Colors.teal;
    if (ratio <= 20) {
      barColor = Colors.redAccent;
    } else if (ratio <= 50) {
      barColor = Colors.orangeAccent;
    }

    bool isCharging = batteryPowerDir == 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _kCardOpacity), 
        borderRadius: BorderRadius.circular(10), 
        border: Border.all(color: Colors.white.withValues(alpha: _kCardBorderOpacity)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('電池電量', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500)),
                  if (isCharging) ...[
                    const SizedBox(width: 2),
                    const Icon(Icons.bolt_rounded, size: 12, color: Colors.orangeAccent),
                  ]
                ],
              ),
              Text(
                batterySoc != null ? '${ratio.toStringAsFixed(0)}%' : '--%', 
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: batterySoc != null ? ratio / 100 : 0.0,
              minHeight: 6,
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

class FirstTimeSetupWizard extends StatefulWidget {
  final String deviceDbId;
  final String inverterSn;
  final VoidCallback onSetupComplete;

  const FirstTimeSetupWizard({
    super.key,
    required this.deviceDbId,
    required this.inverterSn,
    required this.onSetupComplete,
  });

  @override
  State<FirstTimeSetupWizard> createState() => _FirstTimeSetupWizardState();
}

class _FirstTimeSetupWizardState extends State<FirstTimeSetupWizard> {
  int _step = 0; 

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

  Future<void> _executeSetup() async {
    if (_selectedCity == null || _selectedDistrict == null) {
      ScaffoldMessenger.of(context).clearSnackBars(); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請選擇完整的縣市與行政區')));
      return;
    }

    setState(() { _step = 1; }); 

    try {
      final String fullAddress = "$_selectedCity$_selectedDistrict";
      await Supabase.instance.client.from('devices').update({
        'address': fullAddress,
        'tou_settings': {
          'isSeasonModeEnabled': false,
          'summerStartMonth': 6,
          'summerEndMonth': 9,
          'winterSlot0': {'state': 1, 'start': '00:00', 'end': '00:00'},
          'winterSlot1': {'state': 1, 'start': '00:00', 'end': '00:00'},
          'summerSlot0': {'state': 1, 'start': '00:00', 'end': '00:00'},
          'summerSlot1': {'state': 1, 'start': '00:00', 'end': '00:00'}
        }
      }).eq('id', widget.deviceDbId);

      try {
        await Supabase.instance.client.functions.invoke(
          'send-device-command',
          body: {
            'sn': widget.inverterSn,
            'commands': [
              '^S011DST0,06,09\r',
              '^S019TOU0,0,1,0000,0000\r',
              '^S019TOU0,1,1,0000,0000\r'
            ],
          },
        );
      } catch (cmdError) {
        debugPrint('設備離線，指令下發失敗: $cmdError');
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('已儲存安裝區域！充電排程將於設備上線後同步。'), 
            backgroundColor: Colors.orange
          ));
        }
      }

      if (!mounted) return; 
      setState(() { _step = 2; }); 

    } catch (e) {
      if (!mounted) return; 
      ScaffoldMessenger.of(context).clearSnackBars(); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('資料庫儲存失敗，請檢查手機網路連線'), backgroundColor: Colors.redAccent));
      setState(() { _step = 0; }); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: AlertDialog(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.teal.shade400),
            const SizedBox(width: 8),
            const Text('設備初始設定精靈', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
        content: _buildContent(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildContent() {
    switch (_step) {
      case 0:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const Text('請設定安裝區域：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              hint: const Text("選擇縣/市", style: TextStyle(fontSize: 13)),
              items: _taiwanLocations.keys.map((city) => DropdownMenuItem(value: city, child: Text(city, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (val) => setState(() { _selectedCity = val; _selectedDistrict = null; }),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(_selectedCity), 
              initialValue: _selectedDistrict, 
              hint: const Text("選擇行政區", style: TextStyle(fontSize: 13)),
              items: (_selectedCity == null ? <String>[] : _taiwanLocations[_selectedCity]!)
                  .map((dist) => DropdownMenuItem(value: dist, child: Text(dist, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (val) => setState(() => _selectedDistrict = val),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('安裝區域設定完成後，接著將設定初始充電排程', style: TextStyle(fontSize: 11, color: Colors.black45)),
          ],
        );
      case 1:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            CircularProgressIndicator(color: Colors.orangeAccent),
            SizedBox(height: 24),
            Text('正在寫入設備，請稍待...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(height: 20),
          ],
        );
      case 2:
      default:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const Icon(Icons.rocket_launch_rounded, color: Colors.orangeAccent, size: 60),
            const SizedBox(height: 24),
            const Text('恭喜！已完成初始設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
          ],
        );
    }
  }

  List<Widget> _buildActions() {
    if (_step == 0) {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: const Text('稍後設定', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          onPressed: _executeSetup,
          child: const Text('下一步：設定排程', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        )
      ];
    } else if (_step == 2) {
      return [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              Navigator.pop(context);
              widget.onSetupComplete();
            },
            child: const Text('開始使用', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        )
      ];
    }
    return []; 
  }
}