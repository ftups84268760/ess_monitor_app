abstract class DtuProvisionService {
  /// 執行硬體配網，回傳是否成功
  Future<bool> provisionDevice({
    required String ip,
    required String dtuSn,
  });
}