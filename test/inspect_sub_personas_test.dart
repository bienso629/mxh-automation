// Tool doc DB chi xem (khong xoa gi) - chay: flutter test test/inspect_sub_personas_test.dart
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_mxh_auto/core/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('INSPECT: liet ke toan bo persona trong DB that', () async {
    final svc = DatabaseService();
    await svc.init(userKey: 'noreply_typing_vn');
    final personas = await svc.getPersonaProfiles();
    print('TONG CONG: ${personas.length} persona trong DB');
    final sorted = personas.values.toList()
      ..sort((a, b) => a.effectiveEntryKey.compareTo(b.effectiveEntryKey));
    for (final p in sorted) {
      print('entryKey=${p.effectiveEntryKey} | ip=${p.ip} | name=${p.name} | ${p.gender} ${p.age}t | bio=${p.bio.length>30 ? p.bio.substring(0,30) : p.bio}');
    }
  });
}
