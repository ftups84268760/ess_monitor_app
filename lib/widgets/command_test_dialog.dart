import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:io'; // 給 SecurityContext 用的
import 'package:typed_data/typed_data.dart'; // 給 Uint8Buffer 用的

class CommandTestDialog extends StatefulWidget {
  final String deviceSn;
  const CommandTestDialog({super.key, required this.deviceSn});

  @override
  State<CommandTestDialog> createState() => _CommandTestDialogState();
}

class _CommandTestDialogState extends State<CommandTestDialog> {
  final TextEditingController _brokerController = TextEditingController(text: 'vb6a817a.ala.eu-central-1.emqxsl.com');
  final TextEditingController _portController = TextEditingController(text: '8883');
  final TextEditingController _clientIdController = TextEditingController(text: 'FT_TEST_1');
  final TextEditingController _cmdController = TextEditingController();

  bool _isHexMode = true;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _responseLog = '尚未發送指令...\n';

  MqttServerClient? _client;
  StreamSubscription? _subscription;

  String get pubTopic => 'ess/inverter/${widget.deviceSn}/cmd';
  String get subTopic => 'ess/inverter/${widget.deviceSn}/res';

  @override
  void dispose() {
    _subscription?.cancel();
    _client?.disconnect();
    _brokerController.dispose();
    _portController.dispose();
    _clientIdController.dispose();
    _cmdController.dispose();
    super.dispose();
  }

  Future<void> _connectMQTT() async {
    setState(() { _isConnecting = true; });
    final String broker = _brokerController.text.trim();
    final int port = int.tryParse(_portController.text.trim()) ?? 8883;
    final String clientId = _clientIdController.text.trim().isEmpty ? 'FT_TEST_1' : _clientIdController.text.trim();

    _client = MqttServerClient(broker, clientId);
    _client!.port = port;
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 20;

    if (port == 8883) {
      _client!.secure = true;
      _client!.securityContext = SecurityContext.defaultContext;
    }

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs('FTESS', '84268760')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMess;

    try {
      await _client!.connect();
      if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _responseLog += '✅ 已成功連線至 EMQX SSL ($broker:$port)\n';
          _responseLog += '🆔 Client ID: $clientId\n';
          _responseLog += '📡 已訂閱 Response Topic: $subTopic\n---\n';
        });

        _client!.subscribe(subTopic, MqttQos.atMostOnce);
        _subscription = _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
          final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
          final String pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

          Uint8List bytes = Uint8List.fromList(recMess.payload.message);
          String hexStr = bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

          setState(() {
            _responseLog += '📩 [收到回傳] ASCII: $pt\n';
            _responseLog += '   [HEX 格式]: $hexStr\n---\n';
          });
        });
      } else {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
          _responseLog += '❌ EMQX 拒絕連線 (Status: ${_client!.connectionStatus!.returnCode})\n';
        });
        _client!.disconnect();
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isConnected = false;
        _responseLog += '❌ MQTT 連線失敗: $e\n';
      });
      _client!.disconnect();
    }
  }

  void _sendCommand() {
    if (!_isConnected || _client == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請先點擊連線按鈕！')));
      return;
    }

    String inputText = _cmdController.text.trim();
    if (inputText.isEmpty) return;

    Uint8List payloadBytes;

    if (_isHexMode) {
      String cleanHex = inputText.replaceAll(' ', '');
      if (cleanHex.length % 2 != 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('HEX 長度不正確，必須為雙倍字元！')));
        return;
      }
      List<int> bytesList = [];
      for (int i = 0; i < cleanHex.length; i += 2) {
        bytesList.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
      }
      payloadBytes = Uint8List.fromList(bytesList);
    } else {
      payloadBytes = Uint8List.fromList(utf8.encode(inputText));
    }

    final builder = MqttClientPayloadBuilder();
    final buffer = Uint8Buffer()..addAll(payloadBytes);
    builder.addBuffer(buffer);

    _client!.publishMessage(pubTopic, MqttQos.atMostOnce, builder.payload!);

    setState(() {
      _responseLog += '📤 [已發送 -> $pubTopic]\n';
      _responseLog += '   內容: $inputText (${_isHexMode ? "HEX" : "ASCII"})\n';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.terminal_rounded, color: Colors.teal),
              SizedBox(width: 8),
              Text('逆變器指令測試 (MQTT)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _brokerController,
                      decoration: const InputDecoration(labelText: 'EMQX Host', isDense: true, border: OutlineInputBorder()),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _portController,
                      decoration: const InputDecoration(labelText: 'Port', isDense: true, border: OutlineInputBorder()),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _clientIdController,
                      decoration: const InputDecoration(labelText: 'Client ID', isDense: true, border: OutlineInputBorder()),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _isConnected ? Colors.grey : Colors.teal),
                    onPressed: _isConnecting ? null : (_isConnected ? null : _connectMQTT),
                    child: Text(_isConnected ? '已連線' : (_isConnecting ? '連線中' : '連線'), style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  const Text('指令格式：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ChoiceChip(
                    label: const Text('HEX (16進位)', style: TextStyle(fontSize: 11)),
                    selected: _isHexMode,
                    selectedColor: Colors.teal.withValues(alpha: 0.2),
                    onSelected: (v) => setState(() => _isHexMode = true),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('ASCII (字串)', style: TextStyle(fontSize: 11)),
                    selected: !_isHexMode,
                    selectedColor: Colors.teal.withValues(alpha: 0.2),
                    onSelected: (v) => setState(() => _isHexMode = false),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cmdController,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: _isHexMode ? '例: 01 03 00 00 00 02 C4 0B' : '例: QID',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.teal),
                    onPressed: _sendCommand,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              const Text('📡 回傳視窗 (Terminal Output)：', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),

              Container(
                height: 160,
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _responseLog,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}