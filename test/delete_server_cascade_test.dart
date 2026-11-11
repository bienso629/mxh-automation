// Kiem chung luong cascade: xoa San khau -> toan bo nhan vat cung IP bien mat
// ignore_for_file: avoid_print
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:agent_mxh_auto/core/services/persona_service.dart';
import 'package:agent_mxh_auto/core/services/database_service.dart';
import 'package:agent_mxh_auto/models/persona_profile_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Xoa San khau cascade: nhan vat goc + phu + alias IP deu bien mat', () async {
    final db = DatabaseService();
    await db.init(userKey: 'cascade_test_${DateTime.now().millisecondsSinceEpoch}');
    final svc = PersonaService();
    final serverIp = '198.51.100.9';
    final aliasIp = '198.51.100.77';

    // Don du lieu cu neu co
    await db.deletePersonaProfilesByServer(serverIp: serverIp, aliasIps: [aliasIp]);
    for (final key in ['$aliasIp##2']) {
      await db.deletePersonaProfile(key);
    }

    // 1. Tao nhan vat: goc (serverIp), phu (serverIp##2), alias (aliasIp), phu alias (aliasIp##2)
    //    va 1 nhan vat ngoai la cua San khau khac (phai song sot)
    final outsiderIp = '203.0.113.200';
    await db.deletePersonaProfilesByServer(serverIp: outsiderIp);
    final fixtures = [
      PersonaProfile(ip: serverIp, entryKey: serverIp, name: 'Goc', age: 25, gender: 'Nam', bio: 'x', avatarPrompt: ''),
      PersonaProfile(ip: serverIp, entryKey: '$serverIp##2', name: 'Phu 2', age: 25, gender: 'Nam', bio: 'x', avatarPrompt: ''),
      PersonaProfile(ip: aliasIp, entryKey: aliasIp, name: 'Alias goc', age: 25, gender: 'Nam', bio: 'x', avatarPrompt: ''),
      PersonaProfile(ip: aliasIp, entryKey: '$aliasIp##2', name: 'Alias phu', age: 25, gender: 'Nam', bio: 'x', avatarPrompt: ''),
      PersonaProfile(ip: outsiderIp, entryKey: outsiderIp, name: 'Ngoai la', age: 25, gender: 'Nam', bio: 'x', avatarPrompt: ''),
    ];
    for (final p in fixtures) {
      expect(await svc.updatePersona(p), isTrue, reason: 'Tao ${p.effectiveEntryKey}');
    }

    // 2. Xoa San khau theo serverIp + aliasIps
    final removed = await svc.deletePersonasByServerIps(serverIp: serverIp, aliasIps: [aliasIp]);
    print('So nhan vat da xoa: $removed');
    expect(removed, 4, reason: 'Phai xoa dung 4 nhan vat (goc + phu + alias + alias phu)');

    // 3. Cache khong con nhan vat nao thuoc San khau
    final cacheAfter = svc.allPersonas;
    expect(cacheAfter.containsKey(serverIp), isFalse);
    expect(cacheAfter.containsKey('$serverIp##2'), isFalse);
    expect(cacheAfter.containsKey(aliasIp), isFalse);
    expect(cacheAfter.containsKey('$aliasIp##2'), isFalse);
    expect(cacheAfter.containsKey(outsiderIp), isTrue, reason: 'Nhan vat San khau khac phai song sot');

    // 4. DB phai sach sau khi doc lai tu duoi db
    final dbRows = await db.getPersonaProfiles();
    final dbKeys = dbRows.keys.toSet();
    expect(dbKeys.contains(serverIp), isFalse, reason: 'DB khong con nhan vat goc');
    expect(dbKeys.contains('$serverIp##2'), isFalse);
    expect(dbKeys.contains(aliasIp), isFalse);
    expect(dbKeys.contains('$aliasIp##2'), isFalse);
    expect(dbKeys.contains(outsiderIp), isTrue);

    // 5. loadSavedPersonas(forceReload) khong hoi sinh nhan vat da xoa (JSON da duoc don)
    final reloaded = await svc.loadSavedPersonas(forceReload: true);
    expect(reloaded.containsKey(serverIp), isFalse, reason: 'F5 lai khong hoi sinh tu JSON');
    expect(reloaded.containsKey(aliasIp), isFalse);
    expect(reloaded.containsKey(outsiderIp), isTrue);

    // Don sieu dep
    await db.deletePersonaProfilesByServer(serverIp: outsiderIp);
    print('=== CASCADE DELETE TEST PASSED ===');
  });
}
