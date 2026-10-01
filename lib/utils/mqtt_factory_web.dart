import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

MqttClient getMqttClient(String clientId) {
  // 網頁版走 WebSockets 連線 (Port 8084)
  return MqttBrowserClient.withPort('wss://vb6a817a.ala.eu-central-1.emqxsl.com/mqtt', clientId, 8084);
}