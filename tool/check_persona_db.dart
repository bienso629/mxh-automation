// ignore_for_file: avoid_print
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main(List<String> args) async {
  sqfliteFfiInit();
  final home = Platform.environment['HOME'] ?? '.';
  final path = args.isNotEmpty
      ? args[0]
      : '$home/.agent_mxh_auto/chat_history_noreply_typing_vn.db';
  final db = await databaseFactoryFfi.openDatabase(path);
  final rows = await db.query('persona_profiles');
  print('Tong so persona: ${rows.length}');
  final byIp = <String, List<String>>{};
  for (final r in rows) {
    final ip = r['ip']?.toString() ?? '';
    byIp.putIfAbsent(ip, () => []).add('${r['entry_key']} | ${r['name']}');
  }
  print('--- Pho theo IP ---');
  final keys = byIp.keys.toList()..sort();
  for (final ip in keys) {
    print('  $ip:');
    for (final line in byIp[ip]!) {
      print('    - $line');
    }
  }
  await db.close();
}
