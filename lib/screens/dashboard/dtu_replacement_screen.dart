import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '/screens/scanner_screen.dart'; 

class DtuReplacementScreen extends StatefulWidget {
  final String deviceDbId;
  final String inverterSn;

  const DtuReplacementScreen({
    super.key,
    required this.deviceDbId,
    required this.inverterSn,
  });

  @override
  State<DtuReplacementScreen> createState() => _DtuReplacementScreenState();
}

class _DtuReplacementScreenState extends State<DtuReplacementScreen> {
  final TextEditingController _newDtuSnController = TextEditingController();
  final TextEditingController _newDtuIpController = TextEditingController();
  
  bool _isLoading = false;
  String _currentDtuSn = '載入中...';
  String _statusText = '';
  
  // 🎯 新增：紀錄是否正在測試連線中
  bool _isPinging = false; 

  @override
  void initState() {
    super.initState();
    _fetchCurrentDtu();
  }

  Future<void> _fetchCurrentDtu() async {
    try {
      final response = await Supabase.instance.client
          .from('devices')
          .select('dtu_sn')
          .eq('id', widget.deviceDbId)
          .single();
          
      if (mounted) {
        setState(() {
          _currentDtuSn = response['dtu_sn'] ?? '無綁定紀錄';
        });
      }
    } catch (e) {
      debugPrint('取得當前DTU失敗: $e');
      if (mounted) {
        setState(() {
          _currentDtuSn = '讀取失敗';
        });
      }
    }
  }

  Future<void> _scanQRCode() async {
    final String? scannedCode = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    if (scannedCode != null && scannedCode.isNotEmpty) {
      String cleanedCode = scannedCode.trim();
      String upperCode = cleanedCode.toUpperCase();
      
      if (upperCode.contains('SN:')) {
        int startIndex = upperCode.indexOf('SN:') + 3; 
        int endIndex = upperCode.indexOf(',', startIndex); 
        
        if (endIndex == -1) {
          cleanedCode = cleanedCode.substring(startIndex).trim();
        } else {
          cleanedCode = cleanedCode.substring(startIndex, endIndex).trim();
        }
      }
      
      setState(() {
        _newDtuSnController.text = cleanedCode;
      });
      _showSnackBar('✅ 掃描成功');
    }
  }

  void _showSnackBar(String message, {Color color = Colors.orangeAccent}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)), backgroundColor: color));
    }
  }

  // 🎯 新增：DTU 連線測試功能 (移植自設備新增註冊頁面)
  Future<void> _testDtuConnection() async {
    final ip = _newDtuIpController.text.trim();
    if (ip.isEmpty) {
      _showSnackBar('請先輸入 DTU IP', color: Colors.redAccent);
      return;
    }

    setState(() { _isPinging = true; });

    try {
      bool isOnline = false;
      
      // 方法一：嘗試對 Port 80 建立 TCP 連線
      try {
        final socket = await Socket.connect(ip, 80, timeout: const Duration(seconds: 2));
        isOnline = true;
        socket.destroy();
      } catch (_) {
        // 方法二：使用系統內建的 ICMP Ping 指令
        try {
          final result = await Process.run('ping', ['-c', '1', '-W', '2', ip]);
          if (result.exitCode == 0) isOnline = true;
        } catch (_) {}
      }

      if (mounted) {
        if (isOnline) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ DTU連線測試成功', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)), backgroundColor: Colors.orangeAccent));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ 連線測試失敗，請確認手機與DTU是否在相同網路區段'), backgroundColor: Colors.redAccent));
        }
      }
    } finally {
      if (mounted) setState(() { _isPinging = false; });
    }
  }

  Future<bool> _configureNewDtuViaUDP(String ip, String inverterSn) async {
    RawDatagramSocket? udpSocket;
    StreamSubscription? subscription; 
    
    try {
      final dtuAddress = InternetAddress(ip);
      
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
          throw Exception('通訊逾時或失敗 ($cmd)');
        }
      }

      setState(() => _statusText = '喚醒新DTU模組中...');
      for (int i = 0; i < 3; i++) {
        udpSocket.send(utf8.encode('WWW.USR.CN'), broadcastAddress, 48899);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      await Future.delayed(const Duration(milliseconds: 1500));

      setState(() => _statusText = '寫入參數至DTU中...');
      await sendAT('AT+MQTTEN=ON\r\n');
      await sendAT('AT+MQTTVER=4\r\n');
      await sendAT('AT+MQTTCID=$inverterSn\r\n'); 
      await sendAT('AT+MQTTSER=vb6a817a.ala.eu-central-1.emqxsl.com,8883\r\n');
      await sendAT('AT+MQTTAUTH=ON\r\n');
      await sendAT('AT+MQTTUSER=FTESS\r\n');
      await sendAT('AT+MQTTPSW=84268760\r\n');
      await sendAT('AT+MQTTSSL=ON,2,0\r\n');

      setState(() => _statusText = '正在綁定逆變器資料傳輸 Topic...');
      await sendAT('AT+MQTTPUB=1,ON,inverter/telemetry/$inverterSn,0,1,0,OFF,1\r\n'); 
      await sendAT('AT+MQTTSUB=1,ON,inverter/command/$inverterSn,0,0,&#44,1\r\n'); 

      setState(() => _statusText = '設定完成，正在重啟DTU...');
      await sendAT('AT+Z\r\n', expectOk: false);

      return true;
    } catch (e) {
      debugPrint('配置失敗: $e');
      throw Exception('與DTU通訊失敗，詳細錯誤: $e');
    } finally {
      await subscription?.cancel(); 
      udpSocket?.close();
    }
  }

  Future<void> _submitReplacement() async {
    final newDtuSn = _newDtuSnController.text.trim();
    final newDtuIp = _newDtuIpController.text.trim();
    
    if (newDtuSn.isEmpty || newDtuIp.isEmpty) {
      _showSnackBar('請輸入新模組的序號與 IP');
      return;
    }
    if (newDtuSn == _currentDtuSn) {
      _showSnackBar('新序號不可與舊序號相同');
      return;
    }

    setState(() { _isLoading = true; _statusText = '檢查綁定衝突...'; });

    try {
      final checkExist = await Supabase.instance.client
          .from('devices')
          .select('id')
          .eq('dtu_sn', newDtuSn)
          .maybeSingle();

      if (checkExist != null) {
        throw '此DTU序號已被其他設備綁定！';
      }

      await _configureNewDtuViaUDP(newDtuIp, widget.inverterSn);

      setState(() => _statusText = '更新雲端資料庫...');
      await Supabase.instance.client
          .from('devices')
          .update({'dtu_sn': newDtuSn})
          .eq('id', widget.deviceDbId);

      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[850],
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text('模組更換成功', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          content: Text('已成功將設備綁定至新模組\nDTU: $newDtuSn', style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); 
                Navigator.pop(context); 
              },
              child: const Text('完成', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

    } catch (e) {
      _showSnackBar(e.toString(), color: Colors.redAccent);
    } finally {
      if (mounted) setState(() { _isLoading = false; _statusText = ''; });
    }
  }

  @override
  void dispose() {
    _newDtuSnController.dispose();
    _newDtuIpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900], 
      appBar: AppBar(
        title: const Text('通訊模組(DTU)更換', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.grey[850], 
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isLoading 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.orangeAccent),
                  const SizedBox(height: 16),
                  Text(_statusText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[850], 
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[800]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('逆變器序號(SN)', style: TextStyle(fontSize: 12, color: Colors.white54)),
                        const SizedBox(height: 4),
                        Text(widget.inverterSn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Divider(height: 1, color: Colors.white10),
                        ),
                        const Text('原有DTU序號(SN)', style: TextStyle(fontSize: 12, color: Colors.white54)),
                        const SizedBox(height: 4),
                        Text(_currentDtuSn, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('新更換DTU模組資訊', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _newDtuSnController,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'DTU序號(SN)',
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.grey[800], 
                      prefixIcon: const Icon(Icons.qr_code, color: Colors.orangeAccent),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.camera_alt, color: Colors.white70),
                        onPressed: _scanQRCode,
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _newDtuIpController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'DTU IP',
                      labelStyle: const TextStyle(color: Colors.white54),
                      hintText: '請先將手機與DTU在同一網路區段',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: Colors.grey[800],
                      prefixIcon: const Icon(Icons.router, color: Colors.orangeAccent),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  
                  // 🎯 新增這段：右下角的 DTU 連線測試按鈕
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orangeAccent,
                        side: const BorderSide(color: Colors.orangeAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: _isPinging ? null : _testDtuConnection,
                      icon: _isPinging 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.orangeAccent, strokeWidth: 2))
                          : const Icon(Icons.wifi_find_rounded, size: 18),
                      label: Text(_isPinging ? '測試中...' : 'DTU連線測試', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      onPressed: _submitReplacement,
                      child: const Text('模組更換', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}