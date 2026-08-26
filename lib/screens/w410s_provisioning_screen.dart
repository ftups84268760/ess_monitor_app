import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '/screens/scanner_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class W410sProvisioningScreen extends StatefulWidget {
  const W410sProvisioningScreen({super.key});

  @override
  State<W410sProvisioningScreen> createState() => _W410sProvisioningScreenState();
}

class _W410sProvisioningScreenState extends State<W410sProvisioningScreen> {
  int _currentStep = 0;
  final TextEditingController _dtuIpController = TextEditingController();
  final TextEditingController _dtuSnController = TextEditingController();
  final TextEditingController _inverterSnController = TextEditingController();

  double _provisioningProgress = 0.0;
  String _provisioningStatusText = '等待開始...';

/// 🎯 新增：檢查逆變器 SN 是否已經存在於資料庫
  Future<bool> _checkIfDeviceExists(String inverterSn) async {
    try {
      final data = await Supabase.instance.client
          .from('devices')
          .select('sn')
          .eq('sn', inverterSn)
          .limit(1);
      return data.isNotEmpty; // 如果有撈到資料，代表已經註冊過了
    } catch (e) {
      debugPrint('檢查設備是否存在失敗: $e');
      return false; 
    }
  }

  /// 🎯 新增：SN 重複時的警告視窗
  void _showDeviceExistsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('設備已存在', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('此逆變器序號已經存在！\n請重新確認是否掃描正確。', style: TextStyle(color: Colors.white70, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }


  /// 雲端註冊：將逆變器與 DTU 的對應關係寫入 Supabase
  Future<bool> _registerDeviceToCloud(String inverterSn, String dtuSn) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        debugPrint('錯誤：找不到登入的使用者，請確認已登入');
        return false;
      }

      await supabase.from('devices').upsert({
        'user_id': user.id,
        'sn': inverterSn,
        'dtu_sn': dtuSn,
        'name': '儲能主機_$inverterSn',
        'address': '尚未設定',
        'electricity_tariff': '一般累進表燈(住商)',
        'is_online': true,
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
      }, onConflict: 'sn');

      return true;
    } catch (e) {
      debugPrint('設備註冊失敗: $e');
      return false;
    }
  }

  Future<void> _scanQRCode(TextEditingController targetController) async {
    final String? scannedCode = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    if (scannedCode != null && scannedCode.isNotEmpty) {
      // 🎯 關鍵修改：去除字串前後空白，並自動過濾開頭的 "SN:" (不分大小寫)
      String cleanedCode = scannedCode.trim();
      if (cleanedCode.toUpperCase().startsWith('SN:')) {
        cleanedCode = cleanedCode.substring(3); // 截掉前3個字元 ("S", "N", ":")
      }

      setState(() {
        targetController.text = cleanedCode;
      });
      _showSnackBar('✅ 掃描成功');
    }
  }

  /// 🎯 專屬 W410s 的網路 AT 指令配網流程
  Future<bool> _configureW410sViaUDP(String ip, String inverterSn) async {
    RawDatagramSocket? udpSocket;
    StreamSubscription? subscription; 
    
    try {
      final dtuAddress = InternetAddress(ip);
      
      // 動態計算「子網路廣播位址 (Subnet Broadcast)」
      final ipParts = ip.split('.');
      if (ipParts.length == 4) {
        ipParts[3] = '255';
      }
      final subnetBroadcastIp = ipParts.join('.');
      final broadcastAddress = InternetAddress(subnetBroadcastIp);
      
      udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      udpSocket.readEventsEnabled = true;
      udpSocket.broadcastEnabled = true; 

      List<String> receiveBuffer = [];

      subscription = udpSocket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          while (true) {
            final datagram = udpSocket?.receive();
            if (datagram == null) break;
            
            final resp = utf8.decode(datagram.data, allowMalformed: true);
            receiveBuffer.add(resp);
            debugPrint('<= 接收: $resp');
          }
        }
      });

      Future<void> sendAT(String cmd, {bool expectOk = true, InternetAddress? targetIp}) async {
        receiveBuffer.clear(); 
        final target = targetIp ?? dtuAddress; 
        debugPrint('=> 發送至 ${target.address}: ${cmd.replaceAll('\r', '<CR>').replaceAll('\n', '<LF>')}');
        
        udpSocket!.send(utf8.encode(cmd), target, 48899); 
        
        int elapsed = 0;
        bool isSuccess = false;
        
        while (elapsed < 3000) {
          await Future.delayed(const Duration(milliseconds: 100));
          elapsed += 100;
          
          if (receiveBuffer.isNotEmpty) {
            if (!expectOk) {
              isSuccess = true;
              break;
            } else {
              if (receiveBuffer.any((msg) => msg.contains('+OK'))) {
                isSuccess = true;
                break;
              }
            }
          }
        }

        if (!isSuccess) {
          if (receiveBuffer.isEmpty) {
            throw Exception('指令逾時無回應 ($cmd)');
          } else {
            throw Exception('指令執行失敗或未包含 +OK: ${receiveBuffer.join(" | ")}');
          }
        }
      }

// ---------------------------------------------------------
      // Step 1: 喚醒設備 (🎯 加入防掉包的連環敲門機制)
      // ---------------------------------------------------------
      setState(() => _provisioningStatusText = '設定中...');
      
      // 連續廣播 3 次通關密語，每次間隔 300 毫秒，克服 UDP 掉包與 ARP 冷啟動延遲
      for (int i = 0; i < 3; i++) {
        udpSocket.send(utf8.encode('WWW.USR.CN'), broadcastAddress, 48899);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // 敲完門後，給設備 1.5 秒的充裕時間切換到 AT 指令模式
      await Future.delayed(const Duration(milliseconds: 1500));

      // ---------------------------------------------------------
      // Step 2: 寫入 MQTT 基礎與 SSL 參數 
      // ---------------------------------------------------------
      setState(() => _provisioningStatusText = '寫入雲端資料庫...');
      await sendAT('AT+MQTTEN=ON\r\n');
      await sendAT('AT+MQTTVER=4\r\n');
      await sendAT('AT+MQTTCID=$inverterSn\r\n'); 
      await sendAT('AT+MQTTSER=vb6a817a.ala.eu-central-1.emqxsl.com,8883\r\n');
      await sendAT('AT+MQTTAUTH=ON\r\n');
      await sendAT('AT+MQTTUSER=FTESS\r\n');
      await sendAT('AT+MQTTPSW=84268760\r\n');
      
      await sendAT('AT+MQTTSSL=ON,2,0\r\n');

      // ---------------------------------------------------------
      // Step 3: 寫入 PUB 與 SUB 訂閱主題
      // ---------------------------------------------------------
      setState(() => _provisioningStatusText = '正在綁定逆變器資料傳輸 Topic...');
      await sendAT('AT+MQTTPUB=1,ON,inverter/telemetry/$inverterSn,0,1,0,OFF,1\r\n'); 
      await sendAT('AT+MQTTSUB=1,ON,inverter/command/$inverterSn,0,0,&#44,1\r\n'); 

      // ---------------------------------------------------------
      // Step 4: 儲存參數並重啟設備
      // ---------------------------------------------------------
      setState(() => _provisioningStatusText = '設定完成，正在重啟DTU...');
      await sendAT('AT+Z\r\n', expectOk: false);

      return true;
    } catch (e) {
      debugPrint('配置失敗: $e');
      throw Exception('與DTU通訊失敗。詳細錯誤: $e');
    } finally {
      await subscription?.cancel(); 
      udpSocket?.close();
    }
  }
  
  Future<void> _startProvisioningFlow() async {
    final ip = _dtuIpController.text.trim();
    final inverterSn = _inverterSnController.text.trim();
    final dtuSn = _dtuSnController.text.trim();

    if (ip.isEmpty || inverterSn.isEmpty || dtuSn.isEmpty) {
      _showSnackBar('請確認 IP 與兩組設備序號皆已填寫');
      return;
    }

    setState(() {
      _currentStep = 1;
      _provisioningProgress = 0.1;
      _provisioningStatusText = '正在檢查設備序號是否重複...';
    });

    // ---------------------------------------------------------
    // 🎯 需求 1：先檢查資料庫是否已存在此 SN
    // ---------------------------------------------------------
    final isExist = await _checkIfDeviceExists(inverterSn);
    if (isExist) {
      setState(() {
        _currentStep = 0;
        _provisioningProgress = 0.0;
      });
      _showDeviceExistsDialog();
      return; // 終止流程
    }

    try {
      // ---------------------------------------------------------
      // 🎯 需求 2 (前半)：先執行最容易失敗的 UDP 配網
      // ---------------------------------------------------------
      setState(() {
        _provisioningProgress = 0.3;
        _provisioningStatusText = 'Step 1: DTU設定中...';
      });

      // 如果這一步失敗，會直接跳到 catch，不會執行後面的資料庫寫入
      await _configureW410sViaUDP(ip, inverterSn);

      // ---------------------------------------------------------
      // 🎯 需求 2 (後半)：AT 指令全部發送成功後，才寫入 Supabase
      // ---------------------------------------------------------
      setState(() {
        _provisioningProgress = 0.8;
        _provisioningStatusText = 'Step 2: 設備註冊中...';
      });

      final isRegistered = await _registerDeviceToCloud(inverterSn, dtuSn);
      if (!isRegistered) throw Exception('資料庫註冊失敗，請檢查網路連線');

      setState(() {
        _provisioningProgress = 1.0;
        _provisioningStatusText = '配置完成，設備已完成註冊。';
      });

      _showFinalSuccessDialog(inverterSn);

    } catch (e) {
      _showSnackBar('自動化失敗: ${e.toString()}');
      setState(() {
        _currentStep = 0;
        _provisioningProgress = 0.0; // 失敗時退回設定畫面
      });
    }
  }

  // 🎯 成功提示視窗，顯示正確綁定的逆變器 SN Topic
  void _showFinalSuccessDialog(String inverterSn) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Row(
          children: [
            Icon(Icons.rocket_launch, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('DTU配置完成', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('已成功寫入參數！', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            const Text('🎯 已綁定設備上報 Topic:', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text('inverter/telemetry/$inverterSn', style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontFamily: 'monospace')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() { _currentStep = 0; });
            },
            child: const Text('完成', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
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
        title: const Text('設備新增註冊', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
        color: isActive ? Colors.orangeAccent : (_currentStep > stepIndex ? Colors.white70 : Colors.white30),
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
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('設備雲端註冊說明：', style: TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('逆變器透過DTU，將序號(SN)寫入雲端資料庫進行註冊。', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        TextField(
          controller: _inverterSnController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            border: const OutlineInputBorder(),
            labelText: 'Step 1: 掃描逆變器序號(SN)',
            labelStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(Icons.solar_power, color: Colors.orangeAccent, size: 20),
            suffixIcon: IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.white70),
              onPressed: () => _scanQRCode(_inverterSnController),
            ),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _dtuSnController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            border: const OutlineInputBorder(),
            labelText: 'Step 2: 掃描DTU序號(SN)',
            labelStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(Icons.qr_code, color: Colors.orangeAccent, size: 20),
            suffixIcon: IconButton(
              icon: const Icon(Icons.camera_alt, color: Colors.white70),
              onPressed: () => _scanQRCode(_dtuSnController),
            ),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _dtuIpController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          // 限制只能輸入數字與小數點 (可選，能提升輸入體驗)
          keyboardType: const TextInputType.numberWithOptions(decimal: true), 
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            border: OutlineInputBorder(),
            labelText: 'DTU IP(請先將手機與DTU在同一網路區段)',
            // 🎯 新增提示詞與提示詞顏色
            hintText: '請輸入配置的IP位址',
            hintStyle: TextStyle(color: Colors.white30, fontSize: 13), 
            labelStyle: TextStyle(color: Colors.white54),
            prefixIcon: Icon(Icons.router, color: Colors.orangeAccent, size: 20),
          ),
        ),
        const Spacer(),
        
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orangeAccent,
            foregroundColor: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _startProvisioningFlow,
          child: const Text('設備註冊綁定', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
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
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}