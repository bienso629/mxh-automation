// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agent_mxh_auto/core/services/database_service.dart';
import 'package:agent_mxh_auto/core/services/persona_service.dart';
import 'package:agent_mxh_auto/models/persona_profile_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Luu Profile trinh duyet he thong va giu nguyen sau khi F5 (reload DB)', () async {
    final userKey = 'bp_test_${DateTime.now().millisecondsSinceEpoch}';
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final jsonPath = p.join(home, '.agent_mxh_auto', 'personas_$userKey.json');

    final db = DatabaseService();
    final svc = PersonaService();

    addTearDown(() async {
      final dbPath = db.resolvedPath;
      await db.switchUser('teardown_$userKey');
      final teardownPath = db.resolvedPath;
      for (final fPath in [dbPath, teardownPath, jsonPath]) {
        if (fPath != null && File(fPath).existsSync()) {
          try {
            File(fPath).deleteSync();
          } catch (_) {}
        }
      }
    });

    await db.switchUser(userKey);
    svc.switchUser(userKey);

    // 1. Tao nhan vat va gan Profile trinh duyet he thong, sau do Luu lai
    final persona = PersonaProfile(
      ip: '10.20.30.40',
      name: 'Dien vien Test',
      age: 28,
      gender: 'Nam',
      bio: 'Nhan vat kiem thu luu profile trinh duyet',
      avatarPrompt: 'cinematic headshot',
      browserProfileId: 'Profile 1',
      browserProfileName: 'Cong viec (mac dinh)',
    );

    final savedOk = await svc.updatePersona(persona);
    expect(savedOk, isTrue, reason: 'updatePersona phai luu thanh cong vao SQLite');

    // Them ca nhan vat phu cung IP
    final subPersona = PersonaProfile(
      ip: '10.20.30.40',
      entryKey: '10.20.30.40##2',
      name: 'Dien vien Phu',
      age: 24,
      gender: 'Nữ',
      bio: 'Nhan vat phu kiem thu',
      avatarPrompt: 'cinematic portrait',
      browserProfileId: 'Default',
      browserProfileName: 'Ca nhan',
    );
    expect(await svc.updatePersona(subPersona), isTrue);

    // 2. Mo phong F5: xoa cache va tai lai tu Database
    svc.clearCache();
    final afterF5 = await svc.loadSavedPersonas(forceReload: true);

    expect(afterF5['10.20.30.40']?.browserProfileId, equals('Profile 1'));
    expect(afterF5['10.20.30.40']?.browserProfileName, equals('Cong viec (mac dinh)'));
    expect(afterF5['10.20.30.40##2']?.browserProfileId, equals('Default'));
    expect(afterF5['10.20.30.40##2']?.browserProfileName, equals('Ca nhan'));

    // Kiem tra truc tiep tu SQLite (khong qua JSON)
    final directDb = await db.getPersonaProfiles();
    expect(directDb['10.20.30.40']?.browserProfileId, equals('Profile 1'));
    expect(directDb['10.20.30.40']?.browserProfileName, equals('Cong viec (mac dinh)'));

    // 3. Nguoi dung doi ve "Thu muc co lap rieng (mac dinh)" (null) va Luu lai
    final cleared = afterF5['10.20.30.40']!.copyWith(clearBrowserProfile: true);
    expect(await svc.updatePersona(cleared), isTrue);

    svc.clearCache();
    final afterClearF5 = await svc.loadSavedPersonas(forceReload: true);
    expect(afterClearF5['10.20.30.40']?.browserProfileId, isNull,
        reason: 'Khi go chon ve mac dinh, F5 phai giu nguyen null, khong hoi sinh gia tri cu');
    expect(afterClearF5['10.20.30.40']?.browserProfileName, isNull);
  });

  test('Tu dong migrate DB cu thieu cot va khoi phuc browser_profile_id tu JSON', () async {
    sqfliteFfiInit();
    final userKey = 'bp_mig_${DateTime.now().millisecondsSinceEpoch}';
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final dataDir = Directory(p.join(home, '.agent_mxh_auto'));
    if (!dataDir.existsSync()) dataDir.createSync(recursive: true);

    final legacyDbPath = p.join(dataDir.path, 'chat_history_$userKey.db');
    final jsonPath = p.join(dataDir.path, 'personas_$userKey.json');

    final db = DatabaseService();
    final svc = PersonaService();

    addTearDown(() async {
      await db.switchUser('teardown_$userKey');
      final teardownPath = db.resolvedPath;
      for (final fPath in [legacyDbPath, teardownPath, jsonPath]) {
        if (fPath != null && File(fPath).existsSync()) {
          try {
            File(fPath).deleteSync();
          } catch (_) {}
        }
      }
    });

    // 1. Tao DB cu CHUA CO cot browser_profile_id va browser_profile_name
    final rawDb = await databaseFactoryFfi.openDatabase(legacyDbPath);
    await rawDb.execute('''
      CREATE TABLE persona_profiles (
        entry_key TEXT PRIMARY KEY,
        ip TEXT NOT NULL,
        name TEXT NOT NULL,
        age INTEGER DEFAULT 25,
        gender TEXT DEFAULT 'Nam',
        bio TEXT,
        avatar_prompt TEXT,
        external_device_address TEXT,
        use_external_device INTEGER DEFAULT 0,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await rawDb.insert('persona_profiles', {
      'entry_key': '192.168.99.10',
      'ip': '192.168.99.10',
      'name': 'Nhan vat cu',
      'age': 30,
      'gender': 'Nam',
      'bio': 'Bio cu',
      'avatar_prompt': 'prompt',
      'use_external_device': 0,
    });
    await rawDb.close();

    // 2. Tao file JSON chua browser_profile_id ma nguoi dung da luu truoc ban va
    await File(jsonPath).writeAsString(jsonEncode({
      '192.168.99.10': {
        'ip': '192.168.99.10',
        'entry_key': '192.168.99.10',
        'name': 'Nhan vat cu',
        'age': 30,
        'gender': 'Nam',
        'bio': 'Bio cu',
        'avatar_prompt': 'prompt',
        'browser_profile_id': 'Profile 3',
        'browser_profile_name': 'Marketing Team',
      }
    }));

    // 3. Khoi dong DatabaseService & PersonaService -> tu migrate cot + backfill vao SQLite
    await db.switchUser(userKey);
    svc.switchUser(userKey);
    final loaded = await svc.loadSavedPersonas(forceReload: true);

    expect(loaded['192.168.99.10']?.browserProfileId, equals('Profile 3'));
    expect(loaded['192.168.99.10']?.browserProfileName, equals('Marketing Team'));

    // 4. Xoa luon file JSON va F5 lan nua de chung minh SQLite da luu ben vung
    File(jsonPath).deleteSync();
    svc.clearCache();
    final fromSqliteOnly = await svc.loadSavedPersonas(forceReload: true);
    expect(fromSqliteOnly['192.168.99.10']?.browserProfileId, equals('Profile 3'));
    expect(fromSqliteOnly['192.168.99.10']?.browserProfileName, equals('Marketing Team'));
  });
}
