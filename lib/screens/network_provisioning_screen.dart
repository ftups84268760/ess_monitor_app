import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '/screens/scanner_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LuciProvisioningData {
  final String sysauthCookie;
  final String stok;
  final String channelId;

  LuciProvisioningData({
    required this.sysauthCookie,
    required this.stok,
    required this.channelId,
  });
}

class NetworkProvisioningScreen extends StatefulWidget {
  const NetworkProvisioningScreen({super.key});

  @override
  State<NetworkProvisioningScreen> createState() => _NetworkProvisioningScreenState();
}

class _NetworkProvisioningScreenState extends State<NetworkProvisioningScreen> {
  int _currentStep = 0;
  final TextEditingController _dtuIpController = TextEditingController(text: '192.168.3.231');
  final TextEditingController _dtuSnController = TextEditingController();
  final TextEditingController _inverterSnController = TextEditingController();


  double _provisioningProgress = 0.0;
  String _provisioningStatusText = '等待開始...';
  
  LuciProvisioningData? _provisioningData;

  /// 雲端註冊：將逆變器與 DTU 的對應關係寫入 Supabase
  Future<bool> _registerDeviceToCloud(String inverterSn, String dtuSn) async {
    try {
      final supabase = Supabase.instance.client;
      
      // 🎯 1. 取得目前登入的使用者資訊
      final user = supabase.auth.currentUser;
      if (user == null) {
        debugPrint('錯誤：找不到登入的使用者，請確認已登入');
        return false;
      }

      // 🎯 2. 寫入完整資料 (包含 user_id 與所有預設設定)
      await supabase.from('devices').upsert({
        'user_id': user.id,              // 自動綁定當前登入者的 ID
        'sn': inverterSn,                // 逆變器本體序號
        'dtu_sn': dtuSn,                 // DTU 通訊模組序號
        'name': '儲能主機_$inverterSn',      // 自動產生預設設備名稱
        'address': '尚未設定',            // 預設地址
        'electricity_tariff': '一般累進表燈(住商)', // 預設電價費率
        'is_online': true,               // 標記為上線
        
        // 🎯 3. 補回舊版原有的推播開關預設值
        'notification_settings': {
          'grid_off': true,
          'battery_full': true,
          'battery_low': true,
          'battery_charging': false,
          'battery_discharging': false,
          'no_pv': false,
          'load_full': true,
          'load_overload': true,
        },
        // 🎯 4. 補回舊版原有的警報狀態初始值
        'alert_states': {
          'is_grid_off': false,
          'is_battery_full': false,
          'is_battery_low': false,
          'is_charging': false,
          'is_discharging': false,
          'is_no_pv': false,
          'is_load_full': false,
          'is_load_overload': false,
        }
      }, onConflict: 'sn'); // 如果 SN 已存在則執行更新 (Upsert)

      return true;
    } catch (e) {
      debugPrint('設備註冊失敗: $e');
      return false;
    }
  }


  // 🎯 改造後的共用掃描函式
  Future<void> _scanQRCode(TextEditingController targetController) async {
    // 呼叫您之前寫好的相機掃描頁面
    final String? scannedCode = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    // 如果有掃描到內容，就填入指定的控制器中
    if (scannedCode != null && scannedCode.isNotEmpty) {
      setState(() {
        targetController.text = scannedCode;
      });
      _showSnackBar('✅ 掃描成功');
    }
  }

  /// Step 1: 登入並獲取 Token
  Future<Map<String, String>> _loginAndGetLuciToken(String ip) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse('http://$ip/cgi-bin/luci/');
      final request = await client.postUrl(uri);
      
      request.followRedirects = false; 
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');

      final payload = 'luci_username=admin&luci_password=admin';
      final payloadBytes = utf8.encode(payload);
      request.headers.contentLength = payloadBytes.length;
      request.add(payloadBytes);

      final response = await request.close();

      if (response.statusCode != HttpStatus.found && response.statusCode != HttpStatus.seeOther) {
        throw Exception('登入失敗，預期狀態碼 302，卻收到 ${response.statusCode}');
      }

      String? sysauthCookie;
      final rawCookies = response.headers[HttpHeaders.setCookieHeader];
      if (rawCookies != null) {
        for (var rawCookie in rawCookies) {
          final match = RegExp(r'(sysauth=[a-f0-9]+)').firstMatch(rawCookie);
          if (match != null) {
            sysauthCookie = match.group(1);
          }
        }
      }

      if (sysauthCookie == null) throw Exception('找不到 sysauth Cookie');

      String? stok;
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location != null) {
        final RegExp stokRegex = RegExp(r';stok=([a-f0-9]+)');
        final match = stokRegex.firstMatch(location);
        if (match != null) stok = match.group(1);
      }

      if (stok == null) throw Exception('無法從 Location 解析 stok');

      await response.drain();
      return {'sysauth': sysauthCookie, 'stok': stok};
    } finally {
      client.close();
    }
  }

  /// Step 2: 建立 MQTT 通道並攔截動態 ID
  Future<String> _createMqttChannel(String ip, String stok, String sysauthCookie) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse('http://$ip/cgi-bin/luci/;stok=$stok/admin/dtu/channel');
      final request = await client.postUrl(uri);
      
      request.followRedirects = false;
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
      request.headers.set(HttpHeaders.cookieHeader, sysauthCookie);

      final params = {
        'cbi.submit': '1',
        '_newch.name': 'MQTT_Center',
        '_newch.proto': 'MQTT',
        '_newch.enabled': 'ON',
        '_newch.submit': '添加并编辑...'
      };
      
      final payload = params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
      final payloadBytes = utf8.encode(payload);
      
      request.headers.contentLength = payloadBytes.length;
      request.add(payloadBytes);

      final response = await request.close();

      if (response.statusCode != HttpStatus.found && response.statusCode != HttpStatus.seeOther) {
        throw Exception('建立通道失敗，收到狀態碼 ${response.statusCode}');
      }

      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null) throw Exception('伺服器沒有回傳跳轉網址');

      final RegExp channelIdRegex = RegExp(r'/channel/(cfg[a-f0-9]+)');
      final match = channelIdRegex.firstMatch(location);
      
      if (match != null) {
        await response.drain();
        return match.group(1)!;
      } else {
        throw Exception('無法從 URL 解析出通道 ID: $location');
      }
    } finally {
      client.close();
    }
  }

  /// Step 3: 寫入 EMQX 參數並同時建立 PUB 與 SUB Topic
  // 🎯 修改 1：參數新增 String inverterSn
  Future<void> _saveMqttSettingsAndTopic(String ip, String stok, String sysauthCookie, String channelId, String dtuSn, String inverterSn) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    
    try {
      final uri = Uri.parse('http://$ip/cgi-bin/luci/;stok=$stok/admin/dtu/channel/$channelId');

      // ==========================================
      // 0. 發送 GET 請求，抓取真實的動態 Section ID 與「添加」按鈕名稱
      // ==========================================
      final getReq = await client.getUrl(uri);
      getReq.headers.set(HttpHeaders.cookieHeader, sysauthCookie);
      final getRes = await getReq.close();
      final html = await getRes.transform(utf8.decoder).join();

      // 抓取主配置的真實 ID
      final RegExp sectionIdRegex = RegExp(r'name="cbid\.dtu\.([^.]+)\.name"');
      final match = sectionIdRegex.firstMatch(html);
      if (match == null) throw Exception('無法解析出真實的 Section ID');
      final realSectionId = match.group(1)!;

      // 抓取「添加」按鈕的真實 name 屬性 (預設猜測為 _newtopic.submit)
      String addTopicBtnName = '_newtopic.submit';
      final RegExp addBtnRegex = RegExp(r'name="([^"]+)"[^>]*value="添加"');
      final btnMatch = addBtnRegex.firstMatch(html);
      if (btnMatch != null) addTopicBtnName = btnMatch.group(1)!;

      // 建立共用的主伺服器設定
      final mainConfig = {
        'cbi.submit': '1',
        'cbid.dtu.$realSectionId.enabled': 'ON',
        'cbid.dtu.$realSectionId.name': 'ESS_$inverterSn', // 🎯 修改 2：設備名稱帶入逆變器 SN
        'cbid.dtu.$realSectionId.describe': 'MQTT_1',
        'cbid.dtu.$realSectionId.mqtt_version': 'V3.1.1',
        'cbid.dtu.$realSectionId.server': 'vb6a817a.ala.eu-central-1.emqxsl.com',
        'cbid.dtu.$realSectionId.server_port': '8883',
        'cbid.dtu.$realSectionId.client_id': inverterSn,   // 🎯 修改 3：Client ID 嚴格綁定逆變器 SN (確保唯一性)
        'cbid.dtu.$realSectionId.heart_period': '30',
        'cbid.dtu.$realSectionId.rctim': '5',
        'cbid.dtu.$realSectionId.auth': 'ON',
        'cbid.dtu.$realSectionId.username': 'FTESS',
        'cbid.dtu.$realSectionId.password': '84268760',
        'cbid.dtu.$realSectionId.clean_session': 'OFF',
        'cbid.dtu.$realSectionId.tls': 'TLS1.2',
        'cbid.dtu.$realSectionId.tls_auth': 'OFF',
        'cbid.dtu.$realSectionId.workmode': 'pass',
      };

      // ==========================================
      // 請求一：填寫 PUB 參數並模擬點擊「添加」
      // ==========================================
      final requestPub = await client.postUrl(uri);
      requestPub.followRedirects = false;
      requestPub.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
      requestPub.headers.set(HttpHeaders.cookieHeader, sysauthCookie);

      final paramsPub = Map<String, String>.from(mainConfig);
      paramsPub.addAll({
        '_newtopic.type': 'pub',
        '_newtopic.name': 'telemetry_$inverterSn',
      // 🎯 關鍵：動態帶入序號
        '_newtopic.topic': 'inverter/telemetry/$inverterSn',
        '_newtopic.qos': '0',
        '_newtopic.keepmsg': 'OFF',
        '_newtopic.com': 'COM2-232', // 依照您最新截圖修正為 COM2-232
        '_newtopic.describe': '',
        addTopicBtnName: '添加', // 🎯 關鍵：觸發添加動作
      });

      final payloadPub = paramsPub.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
      final bytesPub = utf8.encode(payloadPub);
      requestPub.headers.contentLength = bytesPub.length;
      requestPub.add(bytesPub);

      final responsePub = await requestPub.close();
      await responsePub.drain(); // 清空緩衝區，確保連線可重用

      // ==========================================
      // 請求二：填寫 SUB 參數並再次模擬點擊「添加」
      // ==========================================
      final requestSub = await client.postUrl(uri);
      requestSub.followRedirects = false;
      requestSub.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
      requestSub.headers.set(HttpHeaders.cookieHeader, sysauthCookie);

      final paramsSub = Map<String, String>.from(mainConfig);
      paramsSub.addAll({
        '_newtopic.type': 'sub',
        '_newtopic.name': 'command_$inverterSn',
      // 🎯 關鍵：動態帶入序號
        '_newtopic.topic': 'inverter/command/$inverterSn',
        '_newtopic.qos': '0',
        '_newtopic.keepmsg': 'OFF',
        '_newtopic.com': 'COM2-232',
        '_newtopic.describe': '',
        addTopicBtnName: '添加', // 🎯 關鍵：觸發添加動作
      });
      
      final payloadSub = paramsSub.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
      final bytesSub = utf8.encode(payloadSub);
      requestSub.headers.contentLength = bytesSub.length;
      requestSub.add(bytesSub);

      final responseSub = await requestSub.close();
      await responseSub.drain();

      // ==========================================
      // 請求三：模擬點擊最下方的「保存」，將所有清單寫入設備
      // ==========================================
      final requestSave = await client.postUrl(uri);
      requestSave.followRedirects = false;
      requestSave.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
      requestSave.headers.set(HttpHeaders.cookieHeader, sysauthCookie);

      final paramsSave = Map<String, String>.from(mainConfig);
      paramsSave['cbi.save'] = '保存'; // 🎯 關鍵：最後一步才是保存
      
      final payloadSave = paramsSave.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
      final bytesSave = utf8.encode(payloadSave);
      requestSave.headers.contentLength = bytesSave.length;
      requestSave.add(bytesSave);

      final responseSave = await requestSave.close();
      if (responseSave.statusCode != HttpStatus.ok && responseSave.statusCode != HttpStatus.found) {
        throw Exception('最終保存失敗 (狀態碼: ${responseSave.statusCode})');
      }
      await responseSave.drain();

    } finally {
      client.close();
    }
  }

/// Step 4: 觸發「應用」按鈕，讓 DTU 背景服務重新載入設定
  /// Step 4: 觸發「應用」按鈕，讓 DTU 背景服務重新載入設定
  Future<void> _applyDtuChanges(String ip, String stok, String sysauthCookie) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    
    try {
      final uri = Uri.parse('http://$ip/cgi-bin/luci/;stok=$stok/admin/dtu/channel');
      final request = await client.postUrl(uri);
      
      request.followRedirects = false;
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
      request.headers.set(HttpHeaders.cookieHeader, sysauthCookie);

      // 🎯 關鍵修正：必須同時附上 cbi.submit=1，LuCI 才會認可這是一次有效的表單提交
      final params = {
        'cbi.submit': '1',
        'cbi.apply': '应用',
      };
      
      final payload = params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
      final payloadBytes = utf8.encode(payload);
      
      request.headers.contentLength = payloadBytes.length;
      request.add(payloadBytes);

      final response = await request.close();
      
      if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.found) {
        throw Exception('套用設定失敗 (狀態碼: ${response.statusCode})');
      }
      await response.drain();
      
    } finally {
      client.close();
    }
  }

  Future<void> _startProvisioningFlow() async {
    final ip = _dtuIpController.text.trim();
    final inverterSn = _inverterSnController.text.trim();
    final dtuSn = _dtuSnController.text.trim();

    // 1. 防呆檢查：確保三個欄位都有填寫
    if (ip.isEmpty) {
      _showSnackBar('請輸入 DTU 的 IP 地址');
      return;
    }
    if (inverterSn.isEmpty || dtuSn.isEmpty) {
      _showSnackBar('請掃描並確認逆變器與 DTU 序號皆已填寫');
      return;
    }

    setState(() {
      _currentStep = 1;
      _provisioningProgress = 0.1;
      _provisioningStatusText = 'Step 1: 正在將設備註冊至雲端資料庫...';
    });

    try {
      // ==========================================
      // 【流程 Step 3: 雲端註冊】
      // ==========================================
      final isRegistered = await _registerDeviceToCloud(inverterSn, dtuSn);
      
      if (!isRegistered) {
        throw Exception('雲端註冊失敗，請檢查手機的網際網路連線');
      }

      // ==========================================
      // 【流程 Step 4: 近端硬體配置 (Provisioning)】
      // ==========================================
      setState(() {
        _provisioningProgress = 0.3;
        _provisioningStatusText = 'Step 2: 正在登入 DTU 獲取系統憑證...';
      });

      // 取得 LuCI Token
      final authResult = await _loginAndGetLuciToken(ip);
      
      setState(() {
        _provisioningProgress = 0.5;
        _provisioningStatusText = 'Step 3: 正在建立 MQTT 雲端控制通道...';
      });

      // 建立通道
      final channelId = await _createMqttChannel(ip, authResult['stok']!, authResult['sysauth']!);

      setState(() {
        _provisioningProgress = 0.7;
        _provisioningStatusText = 'Step 4: 寫入設備專屬 Topic 與伺服器參數...';
      });

      // 🎯 關鍵：把 inverterSn 也傳給底層硬體配置函式
      await _saveMqttSettingsAndTopic(ip, authResult['stok']!, authResult['sysauth']!, channelId, dtuSn, inverterSn);
      
      setState(() {
        _provisioningProgress = 0.9;
        _provisioningStatusText = 'Step 5: 正在重啟背景服務 (Apply)...';
      });

      // 套用硬體設定
      await _applyDtuChanges(ip, authResult['stok']!, authResult['sysauth']!);

      await Future.delayed(const Duration(seconds: 3));

      // 流程完美結束
      setState(() {
        _provisioningProgress = 1.0;
        _provisioningStatusText = '配置大功告成！設備已完成註冊並連上 EMQX。';
      });

      // 🎯 關鍵：將 inverterSn 傳給完成畫面，讓它能顯示正確的 Topic 資訊給工程師看
      _showFinalSuccessDialog(inverterSn);

    } catch (e) {
      _showSnackBar('自動化失敗: ${e.toString()}');
      setState(() { 
        _currentStep = 0; 
        _provisioningProgress = 0.0;
      });
    }
  }

  // 🎯 新增參數接收 inverterSn
  void _showFinalSuccessDialog(String inverterSn) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Row(
          children: [
            Icon(Icons.rocket_launch, color: Colors.greenAccent),
            SizedBox(width: 8),
            Text('儲能主機配置完成', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('已成功完成雲端註冊、MQTT 參數寫入與 Topic 綁定！', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            if (_provisioningData != null) ...[
              const Text('🚀 動態 Channel ID:', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)),
                child: Text(_provisioningData!.channelId, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              ),
            ],
            const Text('🎯 已綁定 Topic:', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              // 注意：這邊改用 withValues 避免舊版 opacity 報錯
              decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              // 🎯 動態顯示剛剛綁定成功的 Topic，不再寫死
              child: Text('inverter/telemetry/$inverterSn', style: const TextStyle(color: Colors.tealAccent, fontSize: 13, fontFamily: 'monospace')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // 🎯 第一個 pop：關閉這個 AlertDialog
              Navigator.pop(context);
              // 🎯 第二個 pop：關閉 NetworkProvisioningScreen (配網頁面)，自動退回上一層的「設備清單」
              Navigator.pop(context); 
            },
            child: const Text('回到設備清單', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 4)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('DTU 雲端自動配網', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.grey[850],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.grey[850],
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStepIndicator(0, '1. 設備 IP', _currentStep == 0),
                  const Icon(Icons.chevron_right, color: Colors.white30, size: 16),
                  _buildStepIndicator(1, '2. 自動寫入配置', _currentStep == 1),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: IndexedStack(
                  index: _currentStep,
                  children: [
                    _buildInputConfig(),
                    _buildStepProvisioningStatus(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int stepIndex, String title, bool isActive) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        color: isActive ? Colors.tealAccent : (_currentStep > stepIndex ? Colors.white70 : Colors.white30),
        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildInputConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📢 自動化寫入說明：', style: TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('此步驟將自動完成 LuCI 登入、建立 MQTT 通道，並將儲能主機的資料傳輸 Topic 一次性寫入設備。', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        // ----------------------------------------
        // 1. 逆變器設備序號 (SN) 輸入框
        // ----------------------------------------
        TextField(
          controller: _inverterSnController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            border: const OutlineInputBorder(),
            labelText: 'Step 1: 掃描逆變器SN',
            labelStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(Icons.solar_power, color: Colors.orangeAccent, size: 20), // 換個有質感的 Icon
            suffixIcon: IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.white70),
              // 🎯 關鍵：告訴掃描函式，結果要填入逆變器的 Controller
              onPressed: () => _scanQRCode(_inverterSnController),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ----------------------------------------
        // 2. DTU 設備序號 (SN) 輸入框
        // ----------------------------------------
        TextField(
          controller: _dtuSnController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            border: const OutlineInputBorder(),
            labelText: 'Step 2: 掃描通訊模組(DTU)SN',
            labelStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(Icons.qr_code, color: Colors.tealAccent, size: 20),
            suffixIcon: IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.white70),
              // 🎯 關鍵：告訴掃描函式，結果要填入 DTU 的 Controller
              onPressed: () => _scanQRCode(_dtuSnController),
            ),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _dtuIpController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            border: OutlineInputBorder(),
            labelText: 'DTU 現場區網 IP',
            labelStyle: TextStyle(color: Colors.white54),
            prefixIcon: Icon(Icons.router, color: Colors.tealAccent, size: 20),
          ),
        ),
        const SizedBox(height: 16), // 加上間距
        
        const Spacer(),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _startProvisioningFlow,
          child: const Text('一鍵配網與綁定', style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildStepProvisioningStatus() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: _provisioningProgress,
                  strokeWidth: 8,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                ),
              ),
              Text(
                '${(_provisioningProgress * 100).toInt()} %',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            _provisioningStatusText,
            style: const TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}