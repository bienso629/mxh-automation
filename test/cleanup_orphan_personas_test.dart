// Tool don dep persona "mo coi" chay qua flutter test.
// Persona mo coi = persona co IP khong con thuoc San khau (server) nao con song.
//
// Che do:
//   flutter test test/cleanup_orphan_personas_test.dart                          -> LIET KE (dry-run)
//   CLEANUP_APPLY=1 flutter test test/cleanup_orphan_personas_test.dart          -> XOA THAT (DB+JSON+avatar+browser/device profile)
//
// An toan: persona local (127.x, localhost, ::1) KHONG BAO GIO bi xoa.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agent_mxh_auto/core/services/database_service.dart';
import 'package:agent_mxh_auto/core/services/local_config_service.dart';
import 'package:agent_mxh_auto/core/services/persona_service.dart';

bool _isLocalIp(String ip) {
  final s = ip.trim().toLowerCase();
  return s == '127.0.0.1' || s.startsWith('127.') || s == 'localhost' || s == '::1';
}

String _sanitize(String raw) => raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Don dep persona mo coi (IP khong con San khau nao so huu)', () async {
    final apply = Platform.environment['CLEANUP_APPLY'] == '1';
    final userKey = Platform.environment['CLEANUP_USER_KEY'] ?? 'noreply_typing_vn';
    print('=== DON DEP PERSONA MO COI (user=$userKey, ${apply ? "AP DUNG XOA" : "DRY-RUN"}) ===');

    // 1. Danh sach San khau con song
    final config = LocalConfigService();
    await config.switchUser(userKey);
    final servers = await config.getServers();
    final aliveIps = <String>{};
    for (final s in servers) {
      aliveIps.add(s.serverIp);
      print('San khau song: ${s.id} | ${s.name} | ${s.serverIp}');
    }
    print('Tong IP con song: ${aliveIps.length}');

    // 2. Nap persona
    final db = DatabaseService();
    await db.switchUser(userKey);
    final persona = PersonaService();
    final all = await persona.loadSavedPersonas(forceReload: true);
    print('Tong so persona: ${all.length}');

    // 3. Loc mo coi
    final orphans = <String, dynamic>{};
    final keepers = <String>[];
    all.forEach((key, p) {
      final ip = p.ip.trim();
      if (!_isLocalIp(ip) && !aliveIps.contains(ip)) {
        orphans[key] = p;
      } else {
        keepers.add('$key | ${p.name} | ip=$ip');
      }
    });

    print('\n--- GIU LAI (${keepers.length}) ---');
    for (final k in keepers) {
      print('  + $k');
    }
    print('\n--- MO COI (${orphans.length}) ---');
    for (final e in orphans.entries) {
      print('  - ${e.key} | ${e.value.name} | ip=${e.value.ip}');
    }

    if (orphans.isEmpty) {
      print('\nKhong co persona mo coi nao.');
      return;
    }
    if (!apply) {
      print('\n[DRY-RUN] Chua xoa gi. Chay: CLEANUP_APPLY=1 flutter test test/cleanup_orphan_personas_test.dart');
      return;
    }

    // 4. Xoa that: persona + avatar + browser/device profile
    final home = Platform.environment['HOME'] ?? '/';
    final baseDir = '$home/.agent_mxh_auto';
    final avatarDir = Directory('$baseDir/avatars');
    final browserDir = Directory('$baseDir/browser_profiles');
    final deviceDir = Directory('$baseDir/device_profiles');

    var nPersona = 0, nAvatar = 0, nBrowser = 0, nDevice = 0;

    for (final e in orphans.entries) {
      final p = e.value;
      final ip = p.ip as String;
      final ek = p.effectiveEntryKey as String;

      final ok = await persona.deletePersona(ek);
      if (ok) nPersona++;
      print('Xoa persona "$ek" (${p.name}): $ok');

      final ipSan = _sanitize(ip);
      if (avatarDir.existsSync()) {
        for (final f in avatarDir.listSync(followLinks: false)) {
          if (f is File && f.path.split('/').last.startsWith('avatar_${ipSan}_')) {
            try {
              f.deleteSync();
              nAvatar++;
              print('   avatar: ${f.path.split('/').last}');
            } catch (_) {}
          }
        }
      }
      if (browserDir.existsSync()) {
        for (final c in ['ip_$ipSan', 'ek_${_sanitize(ek)}']) {
          final d = Directory('${browserDir.path}/$c');
          if (d.existsSync()) {
            try {
              d.deleteSync(recursive: true);
              nBrowser++;
              print('   browser profile: $c/');
            } catch (_) {}
          }
        }
      }
      if (deviceDir.existsSync()) {
        final d = Directory('${deviceDir.path}/ip_$ipSan');
        if (d.existsSync()) {
          try {
            d.deleteSync(recursive: true);
            nDevice++;
            print('   device profile: ip_$ipSan/');
          } catch (_) {}
        }
      }
    }

    print('\n=== TONG KET ===');
    print('Persona xoa: $nPersona / ${orphans.length}');
    print('Avatar xoa: $nAvatar');
    print('Browser profile xoa: $nBrowser');
    print('Device profile xoa: $nDevice');

    final after = await persona.loadSavedPersonas(forceReload: true);
    print('\nPersona con lai: ${after.length}');
    after.forEach((k, v) => print('  + $k | ${v.name} | ip=${v.ip}'));

    expect(nPersona, orphans.length, reason: 'Moi persona mo coi phai bi xoa het');
  });
}
