import 'package:flutter_test/flutter_test.dart';
import 'package:agent_mxh_auto/models/persona_profile_model.dart';
import 'package:agent_mxh_auto/core/services/database_service.dart';
import 'package:agent_mxh_auto/core/services/persona_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Tao profile tay cung IP, khong ghi de nhan vat goc', () async {
    final db = DatabaseService();
    await db.init(userKey: 'test_manual_${DateTime.now().millisecondsSinceEpoch}');

    final svc = PersonaService();
    final existing = await svc.loadSavedPersonas();
    final root = existing['192.168.50.10'] ??
        PersonaProfile(
          ip: '192.168.50.10',
          name: 'Nhan vat goc',
          age: 25,
          gender: 'Nam',
          bio: 'Bio goc',
        avatarPrompt: 'anh dai dien',
        );
    final okRoot = await svc.updatePersona(root);
    expect(okRoot, isTrue, reason: 'Luu nhan vat goc that bai');

    // Sinh entryKey moi cho profile phu cung IP
    final nextKey = svc.generateNextEntryKey('192.168.50.10');
    expect(nextKey, equals('192.168.50.10##2'));

    final manual = root.copyWith(
      name: 'Profile tay 1',
      ip: '192.168.50.10',
      entryKey: nextKey,
    );
    final okManual = await svc.updatePersona(manual);
    expect(okManual, isTrue, reason: 'Luu profile tay that bai');

    // Tai lai va kiem tra ca hai ton tai song song
    final after = await svc.loadSavedPersonas();
    expect(after.containsKey('192.168.50.10'), isTrue, reason: 'Mat nhan vat goc - da bi ghi de!');
    expect(after.containsKey(nextKey), isTrue, reason: 'Thieu profile tay');
    expect(after[nextKey]!.ip, equals('192.168.50.10'), reason: 'Profile tay phai dung IP goc');
    expect(after[nextKey]!.name, equals('Profile tay 1'));
    expect(svc.getPersonasForIp('192.168.50.10').length, greaterThanOrEqualTo(2));

    // Xoa rieng profile phu, goc phai con song
    await svc.deletePersona(nextKey);
    final afterDel = await svc.loadSavedPersonas();
    expect(afterDel.containsKey(nextKey), isFalse);
    expect(afterDel.containsKey('192.168.50.10'), isTrue, reason: 'Xoa nham mat nhan vat goc!');
  });
}
