import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient getMqttClient(String clientId) {
  // 手機版走底層 TCP 連線 (Port 8883)
  final client = MqttServerClient.withPort('vb6a817a.ala.eu-central-1.emqxsl.com', clientId, 8883);
  client.secure = true;
  return client;
}