import 'dart:async';
import 'dart:convert';
import 'dart:ui'; // 給 ImageFilter.blur 使用
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:weather_animation/weather_animation.dart';
// 引入核心常數與自訂模組
import '../../core/constants.dart';
import '../../widgets/chart_painters.dart';
import '../settings_screens.dart';
import 'dtu_replacement_screen.dart';

class HomeScreen extends StatefulWidget {
  final String timeString; // 上層傳入的時間字串(目前已用不到，但保留維持介面相容)
  final String lunarString;
  final String deviceDbId;
  final String customInverterName; 
  final bool isDeviceOnline;
  final String accountType; 
  final String inverterSn;

  const HomeScreen({
    super.key,
    required this.timeString,
    required this.lunarString,
    required this.deviceDbId,
    required this.customInverterName,
    required this.isDeviceOnline,
    required this.accountType, 
    required this.inverterSn,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  int? batterySoc;
  double? pvPower;       
  double? gridPower;     
  double? loadPower;     
  double? todaySolar;    
  double? todayLoad;     

  int dcAcPowerDir = 0;
  int linePowerDir = 0;
  int batteryPowerDir = 0;

  Map<String, dynamic>? _touSettings;
  
  String _lastUpdateTime = '--/--/-- --:--:--';
  
  // 🎯 儲存原始電價方案名稱與狀態
  String _rawTariffMode = '一般累進表燈(住商)';
  bool _isStormBackupMode = false;
  
  // 🎯 儲存今日省錢明細與總額
  List<Map<String, dynamic>> _savingsData = [];
  double _todayTotalSavings = 0.0;

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
  RealtimeChannel? _psChannel;
  RealtimeChannel? _testChannel;

  String _locationDisplay = '讀取中...';
  String _weatherDisplay = '';
  int _currentWeatherCode = -1;

  String _formatPower(double? watts) {
    if (watts == null) return '--';
    if (watts >= 1000) {
      return '${(watts / 1000.0).toStringAsFixed(2)} kW';
    }
    return '${watts.toStringAsFixed(0)} W';
  }

  String _formatTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return '--/--/-- --:--:--';
    try {
      DateTime dt = DateTime.parse(raw);
      dt = dt.toLocal().subtract(const Duration(hours: 8));
      
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
             '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (e) {
      return raw; 
    }
  }

  String _getDateHeaderString() {
    final now = DateTime.now();
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final weekdayStr = weekdays[now.weekday - 1];
    final monthStr = now.month.toString().padLeft(2, '0');
    final dayStr = now.day.toString().padLeft(2, '0');
    return '$monthStr/$dayStr $weekdayStr (${widget.lunarString})';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _energyAnimationController = AnimationController(
      value: 0.0,
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _fetchRealLocationAndWeather();
    _fetchInitialTelemetryData();
    _setupRealtimeSubscription();
    _fetchTelemetryDataFromSupabase();

    _autoWeatherRefreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _fetchRealLocationAndWeather();
    });

    _telemetryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchTelemetryDataFromSupabase();
    });
  }

  // 🎯 呼叫資料庫 Function 取得今日每小時收益
  Future<void> _fetchSavingsData() async {
    if (widget.deviceDbId.isEmpty) return;
    try {
      final devRes = await Supabase.instance.client
          .from('devices')
          .select('sn')
          .eq('id', widget.deviceDbId)
          .single();
      final sn = devRes['sn'];

      // 🚨 終極時區修正：直接組裝台灣當地時間字串，避免 +8 小時的時間差干擾
      final now = DateTime.now();
      final startTime = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T00:00:00.000";
      final endTime = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T23:59:59.999";

      final response = await Supabase.instance.client.rpc(
        'calculate_hourly_solar_savings',
        params: {
          'target_device_id': sn,
          'tariff_type': _rawTariffMode,
          'start_time': startTime,
          'end_time': endTime,
        },
      );

      if (mounted && response != null) {
        double total = 0.0;
        List<Map<String, dynamic>> parsedData = [];
        
        for (var row in (response as List)) {
          double saved = double.tryParse(row['saved_twd'].toString()) ?? 0.0;
          total += saved;
          parsedData.add({
            'hour': row['hour_of_day'],
            'saved': saved,
            'period': row['tou_period'] 
          });
        }
        
        parsedData.sort((a, b) => (a['hour'] as int).compareTo(b['hour'] as int));

        setState(() {
          _savingsData = parsedData;
          _todayTotalSavings = total;
        });
      }
    } catch (e) {
      debugPrint('取得收益數據失敗: $e');
    }
  }

  // 🎯 這是初始化資料的函式，請確認有補回 dailyRes 的查詢
  Future<void> _fetchInitialTelemetryData() async {
    try {
      if (widget.deviceDbId.isEmpty) return;
      final devRes = await Supabase.instance.client.from('devices').select('sn').eq('id', widget.deviceDbId).maybeSingle();
      if (devRes == null) return;
      final String sn = (devRes['sn'] ?? '').toString();
      if (sn.isEmpty) return;

      final invPsRes = await Supabase.instance.client.from('telemetry_inv_ps').select().eq('device_id', sn).order('created_at', ascending: false).limit(1);
      final testRes = await Supabase.instance.client.from('telemetry_test').select().eq('device_id', sn).order('created_at', ascending: false).limit(1);
      
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      
      // 🚨 剛剛被誤刪的 dailyRes 查詢在這裡，已經幫您補回了
      final dailyRes = await Supabase.instance.client.from('daily_energy_stats').select().eq('device_id', sn).eq('date', dateStr).limit(1);

      if (mounted) {
        setState(() {
          if (invPsRes.isNotEmpty) _updatePsData(invPsRes.first);
          if (testRes.isNotEmpty) _updateTestData(testRes.first);
          
          if (dailyRes.isNotEmpty) {
            final dailyData = dailyRes.first;
            todaySolar = double.tryParse((dailyData['today_solar_kwh'] ?? 0).toString());
            todayLoad = double.tryParse((dailyData['today_load_kwh'] ?? 0).toString());
          }
        });
      }
    } catch (e) {
      debugPrint('Initial Fetch Error: $e');
    }
  }

  Future<void> _setupRealtimeSubscription() async {
    if (widget.deviceDbId.isEmpty) return;
    final devRes = await Supabase.instance.client.from('devices').select('sn').eq('id', widget.deviceDbId).maybeSingle();
    if (devRes == null) return;
    final String sn = (devRes['sn'] ?? '').toString();
    if (sn.isEmpty) return;

    _psChannel = Supabase.instance.client.channel('public:telemetry_inv_ps:device_id=eq.$sn');
    _psChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert, 
      schema: 'public',
      table: 'telemetry_inv_ps',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'device_id', value: sn),
      callback: (payload) {
        if (mounted) {
          setState(() {
            _updatePsData(payload.newRecord);
          });
        }
      },
    ).subscribe();

    _testChannel = Supabase.instance.client.channel('public:telemetry_test:device_id=eq.$sn');
    _testChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert, 
      schema: 'public',
      table: 'telemetry_test',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'device_id', value: sn),
      callback: (payload) {
        if (mounted) {
          setState(() {
            _updateTestData(payload.newRecord);
          });
        }
      },
    ).subscribe();
  }

  void _updatePsData(Map<String, dynamic> data) {
    double s1 = double.tryParse((data['solar1_input_power'] ?? 0).toString()) ?? 0.0;
    double s2 = double.tryParse((data['solar2_input_power'] ?? 0).toString()) ?? 0.0;
    pvPower = s1 + s2;
    gridPower = double.tryParse((data['ac_in_total_active_power'] ?? 0).toString());
    loadPower = double.tryParse((data['ac_out_total_active_power'] ?? 0).toString());

    batteryPowerDir = int.tryParse((data['battery_power_direction'] ?? 0).toString()) ?? 0;
    
    if (data['created_at'] != null) {
      _lastUpdateTime = _formatTimestamp(data['created_at'].toString());
    }
  }

  void _updateTestData(Map<String, dynamic> data) {
    batterySoc = int.tryParse((data['battery_capacity'] ?? 0).toString());
    dcAcPowerDir = int.tryParse((data['dc_ac_power_direction'] ?? 0).toString()) ?? 0;
    linePowerDir = int.tryParse((data['line_power_direction'] ?? 0).toString()) ?? 0;

    if (data['created_at'] != null) {
      _lastUpdateTime = _formatTimestamp(data['created_at'].toString());
    }
  }

  Future<void> _fetchTelemetryDataFromSupabase() async {
    try {
      if (widget.deviceDbId.isEmpty) return;
      final devRes = await Supabase.instance.client.from('devices').select('sn, is_storm_backup_mode').eq('id', widget.deviceDbId).maybeSingle();
      if (devRes == null) return;
      final String sn = (devRes['sn'] ?? '').toString();
      
      if (sn.isEmpty) return;
      final invPsRes = await Supabase.instance.client.from('telemetry_inv_ps').select().eq('device_id', sn).order('created_at', ascending: false).limit(1);
      final now = DateTime.now();
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final dailyRes = await Supabase.instance.client.from('daily_energy_stats').select().eq('device_id', sn).eq('date', dateStr).limit(1);
      final testRes = await Supabase.instance.client.from('telemetry_test').select().eq('device_id', sn).order('created_at', ascending: false).limit(1);

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

            if (psData['created_at'] != null) {
              _lastUpdateTime = _formatTimestamp(psData['created_at'].toString());
            }

          } else { pvPower = null; gridPower = null; loadPower = null; }

          if (dailyRes.isNotEmpty) {
            final dailyData = dailyRes.first;
            todaySolar = double.tryParse((dailyData['today_solar_kwh'] ?? 0).toString());
            todayLoad = double.tryParse((dailyData['today_load_kwh'] ?? 0).toString());
          } else { todaySolar = null; todayLoad = null; }

          if (testRes.isNotEmpty) {
            final testData = testRes.first;
            batterySoc = int.tryParse((testData['battery_capacity'] ?? 0).toString());
            dcAcPowerDir = int.tryParse((testData['dc_ac_power_direction'] ?? 0).toString()) ?? 0;
            
            linePowerDir = int.tryParse((testData['line_power_direction'] ?? 0).toString()) ?? 0;

            if (invPsRes.isEmpty && testData['created_at'] != null) {
               _lastUpdateTime = _formatTimestamp(testData['created_at'].toString());
            }
          } else { batterySoc = null; }
        });
      }
    } catch (e) {
      if (mounted) setState(() { pvPower = null; gridPower = null; loadPower = null; todaySolar = null; todayLoad = null; batterySoc = null; });
    }
  }

  Future<void> _restoreTouMode() async {
    if (widget.deviceDbId.isEmpty) return;

    try {
      final devData = await Supabase.instance.client
          .from('devices')
          .select('sn')
          .eq('id', widget.deviceDbId)
          .single();
      final String sn = devData['sn'];

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
          .update({'is_storm_backup_mode': false})
          .eq('id', widget.deviceDbId);

      if (mounted) {
        setState(() {
          _isStormBackupMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已成功還原時間電價(TOU)排程設定！'), backgroundColor: Colors.teal)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('還原失敗，請檢查網路連線。'), backgroundColor: Colors.redAccent)
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchRealLocationAndWeather();
      _fetchTelemetryDataFromSupabase();
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
      rate = '累進計費';
    }

    return {'season': season, 'period': period, 'rate': rate};
  }

  Future<void> _fetchRealLocationAndWeather() async {
    try {
      if (widget.deviceDbId.isEmpty) {
        setState(() {
          _locationDisplay = '尚未設定';
          _weatherDisplay = '';
          _currentWeatherCode = -1;
          _rawTariffMode = '一般累進表燈(住商)';
        });
        return;
      }

      final data = await Supabase.instance.client
          .from('devices')
          .select('address, electricity_tariff, tou_settings, is_storm_backup_mode') 
          .eq('id', widget.deviceDbId)
          .maybeSingle();

      if (data == null) return;

      final String rawAddress = (data['address'] ?? '').toString().trim();
      final String tariffMode = data['electricity_tariff'] ?? '一般累進表燈(住商)';

      if (mounted) {
        setState(() {
          _rawTariffMode = tariffMode; 
          _touSettings = data['tou_settings'];
        });
        // 🎯 方案確定後，立刻去要今日收益資料！
        _fetchSavingsData();
      }

      if (rawAddress.isEmpty || rawAddress == '尚未設定' || rawAddress == '未設定安裝地址') {
        if (mounted) {
          setState(() {
            _locationDisplay = '尚未設定';
            _weatherDisplay = '';
            _currentWeatherCode = -1;
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

          if (mounted) {
            setState(() {
              _locationDisplay = '$city$district';
              _weatherDisplay = '$wxText $minTemp~$maxTemp°C';
              _currentWeatherCode = calculatedCode;
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
        });
      }
    }
  }

  int _parseCwaWxToCode(String wx) {
    if (wx.contains('雷')) return 95;
    if (wx.contains('雨') || wx.contains('陣雨')) return 80;
    if (wx.contains('雲') || wx.contains('陰')) return 2;
    return 0;
  }

  Widget _buildWeatherSceneWidget(int code) {
    if (code == 0) {
      return WrapperScene(colors: const [Colors.amberAccent, Colors.orangeAccent], children: const [SunWidget()]);
    } else if (code >= 1 && code <= 3) {
      return WrapperScene(colors: const [Colors.lightBlue, Colors.blueGrey], children: const [CloudWidget()]);
    } else if ((code >= 51 && code <= 65) || (code >= 80 && code <= 82)) {
      return WrapperScene(colors: const [Colors.blueGrey, Colors.indigo], children: const [RainWidget()]);
    } else if (code >= 95) {
      return WrapperScene(colors: const [Colors.indigo, Colors.black87], children: const [RainWidget(), ThunderWidget()]);
    } else {
      return WrapperScene(colors: const [Colors.lightBlue, Colors.amberAccent], children: const [SunWidget()]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _telemetryTimer?.cancel(); 
    _autoWeatherRefreshTimer?.cancel();
    _psChannel?.unsubscribe();
    _testChannel?.unsubscribe();
    _energyAnimationController.dispose();
    super.dispose();
  }

  // 🎯 更新：包含「今日總收益」與「迷你長條圖」的電價卡片
  Widget _buildTariffCard() {
    final details = _getCurrentTariffDetails(_rawTariffMode);
    
    // 動態配給顏色
    final Color seasonColor = details['season'] == '夏月' ? Colors.orange : Colors.blueAccent;
    Color periodColor = Colors.teal;
    if (details['period'] == '尖峰時段') {
      periodColor = Colors.redAccent;
    } else if (details['period'] == '半尖峰時段') {
      periodColor = Colors.orange;
    }

    // 找出長條圖的最大值以計算比例
    double maxSaved = 0;
    for (var item in _savingsData) {
      if (item['saved'] > maxSaved) maxSaved = item['saved'];
    }
    if (maxSaved == 0) maxSaved = 1; // 避免除以零

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24)
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          iconColor: Colors.teal,
          collapsedIconColor: Colors.black38,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          leading: const Icon(Icons.price_change_outlined, color: Colors.teal, size: 18),
          title: const Text('今日發電收益', style: TextStyle(fontSize: 12, color: Colors.black54)),
          // 卡片未展開時，直接秀出今日總省下的錢！
          subtitle: Text(
            'NT\$ ${_todayTotalSavings.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)
          ),
          children: [
            const Divider(height: 1, color: Colors.black12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.4),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('計價模式', style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
                      Text(_rawTariffMode, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                    ],
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 16),
                  
                  // 📊 收益長條圖區塊
                  const Text('今日各時段收益 (NT\$)', style: TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
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
                              
                              // 決定柱狀圖顏色
                              Color barColor = Colors.teal.shade300;
                              if (period == '尖峰') barColor = Colors.redAccent.shade200;
                              if (period == '半尖峰') barColor = Colors.orangeAccent;

                              // 計算柱狀圖高度 (最高 50)
                              double barHeight = (saved / maxSaved) * 50.0;
                              if (barHeight < 2 && saved > 0) barHeight = 2; // 給予最小高度

                              return Container(
                                width: 28,
                                margin: const EdgeInsets.only(right: 6),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(saved > 0 ? saved.toStringAsFixed(1) : '', style: const TextStyle(fontSize: 9, color: Colors.black54)),
                                    const SizedBox(height: 2),
                                    Container(
                                      width: 16,
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
              ),
            ),
          ],
        ),
      ),
    );
  }

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

    Widget buildSlot(String title, Map<String, dynamic>? slot) {
      if (slot == null) return const SizedBox.shrink();
      int state = slot['state'] ?? 0;
      String start = slot['start'] ?? '00:00';
      String end = slot['end'] ?? '00:00';
      
      String stateStr = state == 0 ? '關閉' : (state == 1 ? '充電' : '放電');
      Color stateColor = state == 0 ? Colors.black38 : (state == 1 ? Colors.teal : Colors.orange);

      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: stateColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(stateStr, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: stateColor)),
            ),
            const SizedBox(width: 10),
            Text('$start - $end', style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6), 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: Colors.white24)
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          iconColor: Colors.teal,
          collapsedIconColor: Colors.black38,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          leading: const Icon(Icons.schedule_rounded, color: Colors.teal, size: 18),
          title: const Text('時間電價(TOU)排程', style: TextStyle(fontSize: 12, color: Colors.black54)),
          subtitle: Text(
            isEffectivelyBackup 
                ? '一般運行模式' 
                : (isSeason ? '夏月/非夏月模式' : '全年共用模式'), 
            style: TextStyle(
              fontSize: 12, 
              fontWeight: FontWeight.bold, 
              color: isEffectivelyBackup ? Colors.orange.shade700 : Colors.teal
            )
          ),
          children: [
            const Divider(height: 1, color: Colors.black12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.4),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
              ),
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
                    const SizedBox(height: 10),
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
          ],
        ),
      ),
    );
  }

  Widget _buildStormBackupBanner() {
    if (!_isStormBackupMode) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('惡劣天氣備援執行中', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text('已暫停時間電價(TOU)排程，並盡可能維持電池在高儲備量狀態', style: TextStyle(color: Colors.red.shade700, fontSize: 11)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.teal),
                        SizedBox(width: 8),
                        Text('解除備援模式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    content: const Text(
                      '確定要解除「惡劣天氣備援模式」嗎？\n\n系統將自動還原您上一次設定的「時間電價(TOU)排程」。',
                      style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(), 
                        child: const Text('取消', style: TextStyle(color: Colors.black54)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop(); 
                          _restoreTouMode();           
                        },
                        child: const Text('確定解除', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  );
                },
              );
            },
            child: const Text('解除', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double figmaWidth = 2063.0;
    const double figmaHeight = 1344.0;
    const double figmaRatio = figmaWidth / figmaHeight;
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          if (_currentWeatherCode >= 0)
            Positioned.fill(
              child: Opacity(
                opacity: 0.35,
                child: _buildWeatherSceneWidget(_currentWeatherCode),
              ),
            ),
          Positioned.fill(
            top: kToolbarHeight + statusBarHeight - 12.0,
            bottom: MediaQuery.of(context).size.height * 0.33,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 0.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [                         
                          Text(_getDateHeaderString(), style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text('最後更新: $_lastUpdateTime', style: const TextStyle(fontSize: 9, color: Colors.teal, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end, 
                        children: [
                          Text(
                            _locationDisplay,
                            style: TextStyle(
                              fontSize: 10, 
                              color: (_locationDisplay == '尚未設定') ? Colors.orangeAccent : Colors.black54, 
                              fontWeight: FontWeight.w600
                            )
                          ),
                          if (_weatherDisplay.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              _weatherDisplay,
                              style: const TextStyle(fontSize: 9, color: Colors.black54, fontWeight: FontWeight.w600)
                            ),
                          ],
                        ],
                      ),
                    ],
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
                                      left: getX(218) + (21.0 / figmaWidth) * finalWidth, top: getY(56),
                                      child: buildFixedDashboardItem(title: '電網', value: _formatPower(gridPower)),
                                    ),
                                    Positioned(
                                      left: getX(1457) + (21.0 / figmaWidth) * finalWidth, top: getY(56),
                                      child: buildFixedDashboardItem(title: '太陽能', value: _formatPower(pvPower)),
                                    ),
                                    Positioned(
                                      left: getX(575) + (21.0 / figmaWidth) * finalWidth, top: getY(1189),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('電池', style: TextStyle(color: Colors.black45, fontSize: 11, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 2),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _buildDynamicBatteryIcon(batterySoc),
                                              const SizedBox(width: 4),
                                              Text(
                                              batterySoc != null ? '$batterySoc%' : '--', 
                                              style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Positioned(
                                      left: getX(1457) + (21.0 / figmaWidth) * finalWidth, top: getY(1189),
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
          Positioned.fill(
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
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        children: [
                          Center(child: Container(width: 40, height: 4.5, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)))),
                          const SizedBox(height: 20),
                          
                          _buildStormBackupBanner(),
                          _buildTariffCard(),
                          _buildTouSettingsCard(),
                          
                          _buildMenuRowCard(Icons.wb_sunny, '今日太陽能發電量(kWh)', todaySolar != null ? '${todaySolar!.toStringAsFixed(1)} kWh' : '--'),
                          _buildMenuRowCard(Icons.bolt_rounded, '今日負載用電量(kWh)', todayLoad != null ? '${todayLoad!.toStringAsFixed(1)} kWh' : '--'),
                          _buildMenuRowCard(Icons.battery_charging_full_rounded, '電池電量(SOC)', batterySoc != null ? '$batterySoc %' : '--'),
                          const SizedBox(height: 10),
                          const Divider(color: Colors.black12, height: 1),
                          const SizedBox(height: 10),
                          
                          // 🎯 新增：只有管理員能看到這台設備的「進階維護」入口
                          if (widget.accountType == '系統管理員' || widget.accountType == 'admin') ...[
                          ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            tileColor: Colors.teal.withValues(alpha: 0.1), // 用一點綠色底色區分這是危險動作
                            leading: const CircleAvatar(backgroundColor: Colors.teal, radius: 16, child: Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 16)),
                            title: const Text('通訊模組(DTU)更換', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.teal),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DtuReplacementScreen(
                                  deviceDbId: widget.deviceDbId,
                                  inverterSn: widget.inverterSn,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          ],

                          ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            tileColor: Colors.white.withValues(alpha: 0.5),
                            leading: const CircleAvatar(backgroundColor: Colors.teal, radius: 16, child: Icon(Icons.settings_suggest_rounded, color: Colors.white, size: 16)),
                            title: const Text('設定', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black38),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => SettingsSubMenuScreen(deviceDbId: widget.deviceDbId)),
                              );
                              _fetchRealLocationAndWeather();
                            },
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuRowCard(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: Colors.teal, size: 18),
        title: Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        trailing: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
      ),
    );
  }

  Widget buildFixedDashboardItem({required String title, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(color: Colors.black45, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
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
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 19.0 * (soc / 100.0), 
              decoration: BoxDecoration(
                color: batteryColor,
                borderRadius: BorderRadius.circular(1.0),
              ),
            ),
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
}