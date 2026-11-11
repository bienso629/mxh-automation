// ignore_for_file: avoid_print
// Kiem chung: xoa Server 100 (built-in) phai duoc ghi nho vinh viet.
// Sau khi xoa, nhieu lan getServers() tiep theo KHONG duoc hoi sinh server do.
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_mxh_auto/core/services/local_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Xoa Server 100 -> khong hoi sinh qua cac lan getServers() (F5)', () async {
    final svc = LocalConfigService();
    await svc.switchUser('removaltest_${DateTime.now().millisecondsSinceEpoch}');

    // 1. Lan load dau: server 100 built-in phai duoc tu them (lan dau tien)
    var servers = await svc.getServers();
    print('Lan 1: ${servers.map((s) => s.serverIp).toList()}');
    expect(servers.any((s) => s.serverIp == '103.74.116.119'), isTrue,
        reason: 'Server 100 phai duoc tu them lan dau');

    // 2. Xoa Server 100
    final ok = await svc.deleteServer('103.74.116.119');
    expect(ok, isTrue, reason: 'deleteServer phai thanh cong');

    // 3. F5 nhieu lan: server 100 KHONG duoc quay lai
    for (int i = 0; i < 3; i++) {
      servers = await svc.getServers();
      print('F5 lan ${i + 2}: ${servers.map((s) => s.serverIp).toList()}');
      expect(servers.any((s) => s.serverIp == '103.74.116.119'), isFalse,
          reason: 'Server 100 da bi xoa, F5 lan ${i + 2} KHONG duoc hoi sinh');
    }

    // 4. Doc config truc tiep: removed_builtin_servers phai duoc luu
    final cfg = await svc.loadConfig();
    final removed = (cfg['removed_builtin_servers'] as List?)?.map((e) => e.toString()).toList() ?? [];
    print('removed_builtin_servers = $removed');
    expect(removed, containsAll(['srv_server_100', '103.74.116.119']),
        reason: 'Danh sach xoa built-in phai duoc ghi nho trong config');
  });
}
