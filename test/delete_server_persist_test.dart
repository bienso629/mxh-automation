// ignore_for_file: avoid_print
// Test: xoa san khau xong tai lai (F5) phai khong con trong danh sach.
// Kiem chung vong doi du lieu server: encrypt -> luu -> giai ma -> xoa -> luu -> tai lai.
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_mxh_auto/core/services/encryption_service.dart';
import 'dart:convert';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Xoa san khau xong tai lai: server da xoa phai bien mat', () async {
    final enc = EncryptionService();
    final dir = await Directory.systemTemp.createTemp('agent_state_test');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // 1. Lap du lieu 2 san khau, ma hoa nhu luc app luu len dia
    final servers = [
      {'id': 'srv_a', 'name': 'San khau A', 'server_ip': '1.1.1.1', 'ssh_port': 22, 'ssh_user': 'root', 'ssh_pass': 'x', 'is_selected': true},
      {'id': 'srv_b', 'name': 'San khau B', 'server_ip': '2.2.2.2', 'ssh_port': 22, 'ssh_user': 'root', 'ssh_pass': 'x', 'is_selected': false},
    ];
    final stateFile = File('${dir.path}/appstate_servers.json');
    Future<void> persist(List<Map<String, dynamic>> list) async {
      await stateFile.writeAsString(jsonEncode({'servers': enc.encryptValue(jsonEncode(list))}));
    }

    Future<List<Map<String, dynamic>>> reload() async {
      final decoded = jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      final decrypted = enc.decryptValue(decoded['servers']);
      return (jsonDecode(decrypted) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    await persist(servers);

    // 2. Tai lai lan 1 (mo phong truoc khi xoa)
    var loaded = await reload();
    expect(loaded.length, 2);

    // 3. Xoa san khau B (mo phong deleteServer: removeWhere theo id/server_ip)
    loaded.removeWhere((item) => item['id'] == 'srv_b' || item['server_ip'] == 'srv_b');
    await persist(loaded);

    // 4. F5: tai lai lan 2
    final reloaded = await reload();

    // 5. Kiem chung: srv_b phai mat hoan toan
    expect(reloaded.any((s) => s['id'] == 'srv_b'), isFalse,
        reason: 'Server da xoa khong duoc hoi sinh sau khi tai lai');
    expect(reloaded.length, 1);
    expect(reloaded.first['id'], 'srv_a');
    print('=> PASSED: xoa san khau xong F5 khong con trong danh sach');
  });
}
