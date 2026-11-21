import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agent_mxh_auto/core/services/database_service.dart';
import 'package:agent_mxh_auto/core/services/local_config_service.dart';
import 'package:agent_mxh_auto/core/services/multi_account_service.dart';
import 'package:agent_mxh_auto/core/services/persona_service.dart';
import 'package:agent_mxh_auto/core/services/storage_service.dart';
import 'package:agent_mxh_auto/models/persona_profile_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Co lap du lieu da tai khoan (Logout -> Login moi -> Logout -> Login cu)', () {
    test('Tai khoan cu giu nguyen toan bo profiles sau khi chuyen qua tai khoan moi va xoa tren tai khoan moi', () async {
      SharedPreferences.setMockInitialValues({});
      final ts = DateTime.now().millisecondsSinceEpoch;
      final keyA = 'acct_old_$ts';
      final keyB = 'acct_new_$ts';
      final dataDir = DatabaseService.resolveDefaultDataDir();

      final db = DatabaseService();
      final cfg = LocalConfigService();
      final persona = PersonaService();

      addTearDown(() async {
        await db.closeForLogout();
        await cfg.clearForLogout();
        persona.switchUser('');
        for (final k in [keyA, keyB]) {
          for (final fname in ['chat_history_$k.db', 'personas_$k.json', 'config_$k.json']) {
            final f = File(p.join(dataDir, fname));
            if (f.existsSync()) {
              try {
                f.deleteSync();
              } catch (_) {}
            }
          }
        }
      });

      // 1. Tai khoan cu A dang nhap va tao 4 profiles tren 127.0.0.1
      await db.switchUser(keyA);
      await cfg.switchUser(keyA);
      persona.switchUser(keyA);

      final fixturesA = [
        PersonaProfile(ip: '127.0.0.1', entryKey: '127.0.0.1', name: 'Nhà văn Lâm Vũ', age: 41, gender: 'Nam', bio: 'Bio A1', avatarPrompt: ''),
        PersonaProfile(ip: '127.0.0.1', entryKey: '127.0.0.1##2', name: 'Trường Tồn', age: 54, gender: 'Nam', bio: 'Bio A2', avatarPrompt: ''),
        PersonaProfile(ip: '127.0.0.1', entryKey: '127.0.0.1##3', name: 'Vk', age: 35, gender: 'Nữ', bio: 'Bio A3', avatarPrompt: ''),
        PersonaProfile(ip: '127.0.0.1', entryKey: '127.0.0.1##4', name: 'Nguyễn Ên', age: 25, gender: 'Nam', bio: 'Bio A4', avatarPrompt: ''),
      ];
      for (final item in fixturesA) {
        expect(await persona.updatePersona(item), isTrue);
      }
      expect((await persona.loadSavedPersonas(forceReload: true)).length, 4);

      // 2. Tai khoan A dang xuat
      await db.closeForLogout();
      await cfg.clearForLogout();
      persona.switchUser('');

      // 3. Tai khoan moi B dang nhap
      await db.switchUser(keyB);
      await cfg.switchUser(keyB);
      persona.switchUser(keyB);

      // Tai khoan moi B tuyet doi KHONG ke thua profiles cua A hay personas.json toan cuc
      final personasBInitial = await persona.loadSavedPersonas(forceReload: true);
      expect(personasBInitial, isEmpty, reason: 'Tai khoan moi khong duoc nhiem profile tu tai khoan khac hoac file global');

      // Tai khoan B tao profile rieng cung IP 127.0.0.1 roi xoa sach (mo phong xoa profile / xoa san khau)
      await persona.updatePersona(PersonaProfile(
        ip: '127.0.0.1',
        entryKey: '127.0.0.1',
        name: 'Nhan vat B',
        age: 22,
        gender: 'Nam',
        bio: 'Bio B',
        avatarPrompt: '',
      ));
      await persona.deletePersonasByServerIps(serverIp: '127.0.0.1');
      expect((await persona.loadSavedPersonas(forceReload: true)), isEmpty);

      // 4. Tai khoan B dang xuat
      await db.closeForLogout();
      await cfg.clearForLogout();
      persona.switchUser('');

      // 5. Tai khoan cu A dang nhap lai
      await db.switchUser(keyA);
      await cfg.switchUser(keyA);
      persona.switchUser(keyA);

      final restoredA = await persona.loadSavedPersonas(forceReload: true);
      expect(restoredA.length, 4, reason: 'Toan bo 4 profile cua tai khoan cu A phai con nguyen ven');
      expect(restoredA['127.0.0.1']?.name, 'Nhà văn Lâm Vũ');
      expect(restoredA['127.0.0.1##2']?.name, 'Trường Tồn');
      expect(restoredA['127.0.0.1##3']?.name, 'Vk');
      expect(restoredA['127.0.0.1##4']?.name, 'Nguyễn Ên');

      // 6. Kiem tra: goi updatePersona NGAY sau switchUser (chua loadSavedPersonas) khong duoc xoa mat 3 profile kia trong file JSON
      persona.switchUser('');
      persona.switchUser(keyA);
      await persona.updatePersona(restoredA['127.0.0.1']!.copyWith(bio: 'Bio A1 updated'));
      final afterImmediateUpdate = await persona.loadSavedPersonas(forceReload: true);
      expect(afterImmediateUpdate.length, 4);
      expect(afterImmediateUpdate['127.0.0.1']?.bio, 'Bio A1 updated');
      expect(afterImmediateUpdate['127.0.0.1##4']?.name, 'Nguyễn Ên');
    });

    test('MultiAccountService hop nhat theo uid (username vs email) va giu nguyen userKey', () async {
      SharedPreferences.setMockInitialValues({});
      final multi = MultiAccountService();

      // Lan 1 dang nhap bang email
      await multi.saveAccount(
        'noreply.typing.vn@gmail.com',
        {
          'user': {'id': '1', 'name': 'admin', 'email': 'noreply.typing.vn@gmail.com', 'groups': ['administrators']},
          'profile': {'id': '1', 'name': 'admin', 'email': 'noreply.typing.vn@gmail.com', 'groups': ['administrators']},
        },
        uid: '1',
        userKey: 'noreply_typing_vn',
      );

      // Lan 2 tim theo username "admin" hoac uid "1" phai khop cung 1 tai khoan va giu nguyen userKey
      final matchedByUid = await multi.findMatchingAccount(uid: '1', username: 'admin');
      expect(matchedByUid, isNotNull);
      expect(matchedByUid!.userKey, 'noreply_typing_vn');
      expect(matchedByUid.email, 'noreply.typing.vn@gmail.com');

      // Kiem tra chong trung khoa cho 2 email khac domain
      expect(StorageService.sanitizeEmailWithDomain('hung@gmail.com'), 'hung__gmail_com');
      expect(StorageService.sanitizeEmailWithDomain('hung@type.vn'), 'hung__type_vn');
      expect(
        StorageService.sanitizeEmailWithDomain('hung@gmail.com'),
        isNot(StorageService.sanitizeEmailWithDomain('hung@type.vn')),
      );
    });
  });
}
