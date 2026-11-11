// ignore_for_file: avoid_print
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_mxh_auto/core/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MIGRATION: DB cu (ip PRIMARY KEY) -> giu du lieu + cho phep nhieu nhan vat cung IP', () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final dbPath = '${Directory.current.path}/chat_history_migtest.db';
    final f = File(dbPath);
    if (f.existsSync()) f.deleteSync();

    // 1. Tao DB CU dung schema cu: ip TEXT PRIMARY KEY, khong co entry_key
    final old = await factory.openDatabase(dbPath);
    await old.execute('''
      CREATE TABLE persona_profiles (
        ip TEXT PRIMARY KEY,
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
    await old.insert('persona_profiles', {
      'ip': '192.168.50.66',
      'name': 'Nhan vat goc',
      'age': 45,
      'gender': 'Nam',
      'bio': 'bio goc',
      'avatar_prompt': 'avatar goc',
      'use_external_device': 0,
      'updated_at': '2025-01-01T00:00:00.000',
    });
    await old.close();

    // 2. Mo qua DatabaseService -> tu dong chay migration rebuild
    final svc = DatabaseService();
    await svc.init(userKey: 'migtest');

    // 3. Mo lai file DB de kiem tra ket qua migration
    final db = await factory.openDatabase(dbPath);
    final rows = await db.query('persona_profiles',
        where: "entry_key = ? OR ip = ?", whereArgs: ['192.168.50.66', '192.168.50.66']);
    print('So row sau migration: ${rows.length}');
    for (final r in rows) {
      print('row: entry_key=${r['entry_key']} ip=${r['ip']} name=${r['name']} bio=${r['bio']}');
    }
    expect(rows.length, 1, reason: 'Nhan vat goc phai con dung 1 row');
    final goc = rows.first;
    expect(goc['name'], 'Nhan vat goc');
    expect(goc['bio'], 'bio goc');
    expect(goc['age'], 45);
    expect(goc['entry_key'], '192.168.50.66');

    // 4. INSERT nhan vat PHU cung IP -> phai thanh cong (schema cu se BI GHI DE!)
    await db.insert('persona_profiles', {
      'entry_key': '192.168.50.66##2',
      'ip': '192.168.50.66',
      'name': 'Nhan vat phu',
      'age': 20,
      'gender': 'Nam',
      'bio': 'bio phu',
      'updated_at': '2025-06-01T00:00:00.000',
    }, conflictAlgorithm: ConflictAlgorithm.abort);

    final all = await db.query('persona_profiles');
    print('Tong so row cuoi cung: ${all.length}');
    for (final r in all) {
      print('- ${r['entry_key']} | ${r['name']}');
    }
    expect(all.length, 2, reason: '2 nhan vat cung IP phai song chung');

    // 5. Trung entry_key phai bi tu choi (PRIMARY KEY moi)
    var threw = false;
    try {
      await db.insert('persona_profiles', {
        'entry_key': '192.168.50.66##2',
        'ip': '192.168.50.66',
        'name': 'Trung lap',
        'updated_at': 'x',
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    } catch (e) {
      threw = true;
      print('Insert trung entry_key bi tu choi (DUNG)');
    }
    expect(threw, true, reason: 'Trung entry_key phai bi tu choi');

    await db.close();
    if (f.existsSync()) f.deleteSync();
    print('=== MIGRATION TEST PASSED ===');
  });
}
