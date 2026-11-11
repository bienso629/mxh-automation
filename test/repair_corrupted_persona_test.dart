// Tool sua du lieu: persona bi nhiem entryKey vao cot ip (vi du ip='127.0.0.1##2')
// se duoc re-assign ve IP that va entryKey sach. Chay: flutter test test/repair_corrupted_persona_test.dart
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_mxh_auto/core/services/persona_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('REPAIR: re-assign persona co cot ip nhiem entryKey (ip##n) ve IP that', () async {
    final svc = PersonaService();
    svc.switchUser('noreply_typing_vn');
    final all = await svc.loadSavedPersonas(forceReload: true);

    // Tim persona bi nhiem: cot ip khong dung dinh dang IPv4
    final ipv4 = RegExp(r'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$');
    final corrupted = all.values.where((p) => !ipv4.hasMatch(p.ip)).toList();
    print('Phat hien ${corrupted.length} persona bi nhiem entryKey vao cot ip');
    for (final p in corrupted) {
      print('  LOI: entryKey=${p.effectiveEntryKey} | ip=${p.ip} | name=${p.name}');
    }

    for (final p in corrupted) {
      // IP that = phan truoc dau '##' dau tien
      final realIp = p.ip.split('##').first;
      if (!ipv4.hasMatch(realIp)) {
        print('  BQ: khong xac dinh duoc IP that cho ${p.effectiveEntryKey}, bo qua');
        continue;
      }
      // Sinh entryKey sach duoi IP that
      final newKey = svc.generateNextEntryKey(realIp);
      print('  SUA: ${p.effectiveEntryKey} -> entryKey=$newKey, ip=$realIp');

      // Xoa ban ghi cu (quet sach DB + JSON) roi luu ban ghi moi duoi khoa dung
      await svc.deletePersona(p.effectiveEntryKey);
      final fixed = p.copyWith(ip: realIp, entryKey: newKey);
      final ok = await svc.updatePersona(fixed);
      print('  => Luu moi: ${ok ? "THANH CONG" : "THAT BAI"}');
    }

    // Tai lai va bao cao trang thai cuoi
    final after = await svc.loadSavedPersonas(forceReload: true);
    print('=== SAU KHI SUA: ${after.length} persona ===');
    final sorted = after.values.toList()
      ..sort((a, b) => a.effectiveEntryKey.compareTo(b.effectiveEntryKey));
    for (final p in sorted) {
      print('entryKey=${p.effectiveEntryKey} | ip=${p.ip} | name=${p.name}');
      expect(ipv4.hasMatch(p.ip), isTrue, reason: 'Cot ip phai la IPv4 hop le');
    }
  });
}
