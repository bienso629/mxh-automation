import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:agent_mxh_auto/core/services/cli_automation_bridge_service.dart';
import 'package:agent_mxh_auto/core/services/database_service.dart';
import 'package:agent_mxh_auto/core/services/ldplayer_adb_discovery.dart';
import 'package:agent_mxh_auto/core/services/persona_service.dart';
import 'package:agent_mxh_auto/core/services/socks5_proxy_service.dart';
import 'package:agent_mxh_auto/models/persona_profile_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LDPlayer & Android Studio ADB Discovery Parser', () {
    test('Doc file leidian*.config UTF-8 tieng Viet va bo qua VM da xoa', () async {
      final tempRoot = await Directory.systemTemp.createTemp('ldplayer_cfg_test_');
      addTearDown(() async {
        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final vmsDir = Directory(p.join(tempRoot.path, 'vms'))..createSync(recursive: true);
      final configDir = Directory(p.join(vmsDir.path, 'config'))..createSync(recursive: true);

      // Tao thu muc VM cho index 0 va 1, khong tao index 2 (mo phong VM #2 da bi xoa)
      Directory(p.join(vmsDir.path, 'leidian0')).createSync();
      Directory(p.join(vmsDir.path, 'leidian1')).createSync();

      // File global leidians.config phai bi bo qua
      File(p.join(configDir.path, 'leidians.config')).writeAsStringSync(jsonEncode({
        'nextCheckupdateTime': 0,
      }));

      File(p.join(configDir.path, 'leidian0.config')).writeAsStringSync(jsonEncode({
        'statusSettings.playerName': 'LDPlayer Gốc',
        'basicSettings.adbDebug': 1,
        'propertySettings.phoneManufacturer': 'samsung',
        'propertySettings.phoneModel': 'SM-S908E',
      }));

      File(p.join(configDir.path, 'leidian1.config')).writeAsStringSync(jsonEncode({
        'statusSettings': {'playerName': 'Nhân vật TikTok, Số 1'},
        'basicSettings': {'adbDebug': 1},
        'propertySettings': {
          'phoneManufacturer': 'ASUS',
          'phoneModel': 'ASUS_I003DD',
        },
      }));

      File(p.join(configDir.path, 'leidian2.config')).writeAsStringSync(jsonEncode({
        'statusSettings.playerName': 'VM Đã Xóa',
      }));

      final configs = LdPlayerAdbParser.readLdPlayerConfigsFromDir(
        configDir,
        vmsDir: vmsDir,
      );

      expect(configs.keys.toSet(), equals({0, 1}));
      expect(configs[0]?.playerName, equals('LDPlayer Gốc'));
      expect(configs[0]?.adbDebug, equals(1));
      expect(configs[1]?.playerName, equals('Nhân vật TikTok, Số 1'));

      // Ket hop voi output ldconsole.exe list2 (10 cot LDPlayer 9)
      const list2Output = '''
0,LDPlayer G?c,0,0,1,12450,9820,720,1280,320
1,Nh?n v?t TikTok, S? 1,198204,65812,1,15200,14110,720,1280,320
3,Clone Moi Chua Chay,0,0,0,-1,-1,720,1280,320
''';

      final instances = LdPlayerAdbParser.parseLdConsoleList2Output(
        list2Output,
        configsByIndex: configs,
      );

      expect(instances.length, equals(3));
      expect(instances[0].index, equals(0));
      expect(instances[0].name, equals('LDPlayer Gốc'));
      expect(instances[0].isRunning, isTrue);

      expect(instances[1].index, equals(1));
      expect(instances[1].name, equals('Nhân vật TikTok, Số 1'));
      expect(instances[1].isRunning, isTrue);

      expect(instances[2].index, equals(3));
      expect(instances[2].name, equals('Clone Moi Chua Chay'));
      expect(instances[2].isRunning, isFalse);
    });

    test('Khu trung lap adb devices -l va hop nhat LDPlayer + ADB + Android Studio AVD', () {
      // Mo phong Android Studio hien thi dong thoi:
      // - emulator-5554 + 127.0.0.1:5555 (cung 1 LDPlayer #0)
      // - emulator-5556 (LDPlayer #1 dang chay)
      // - emulator-5558 (Android Studio AVD chuẩn: AI_Type)
      // - 192.168.1.88:5555 (Giả lập LDPlayer kết nối qua ADB TCP vào Android Studio)
      const adbOutput = '''
List of devices attached
emulator-5554          device product:b0qxxx model:SM_S908E device:b0q transport_id:1
127.0.0.1:5555         device product:b0qxxx model:SM_S908E device:b0q transport_id:2
emulator-5556          device product:ROG3 model:ASUS_I003DD device:ASUS_I003_1 transport_id:3
emulator-5558          device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64 device:emu64xa transport_id:4
192.168.1.88:5555      device product:aosp_x86_64 model:Pixel_7_Pro device:generic_x86_64 transport_id:5
emulator-5560          offline
''';

      final adbRecords = LdPlayerAdbParser.parseAdbDevicesLongOutput(adbOutput);
      // 127.0.0.1:5555 gop vao emulator-5554, emulator-5560 offline bi loai -> con 4 thiet bi online
      expect(adbRecords.length, equals(4));
      expect(adbRecords[0].serial, equals('emulator-5554'));
      expect(adbRecords[0].matchesSerial('127.0.0.1:5555'), isTrue);

      final propsMap = <String, AdbGetpropSummary>{
        'emulator-5554': LdPlayerAdbParser.parseAndroidGetpropOutput('''
[ro.product.manufacturer]: [samsung]
[ro.product.model]: [SM-S908E]
[ro.hardware]: [vbox86]
[init.svc.vbox86-setup]: [stopped]
'''),
        'emulator-5556': LdPlayerAdbParser.parseAndroidGetpropOutput('''
[ro.product.manufacturer]: [ASUS]
[ro.product.model]: [ASUS_I003DD]
[ro.ld.version]: [9.0.71]
'''),
        'emulator-5558': LdPlayerAdbParser.parseAndroidGetpropOutput('''
[ro.boot.qemu.avd_name]: [AI_Type]
[ro.product.manufacturer]: [Google]
[ro.product.model]: [sdk_gphone64_x86_64]
[ro.kernel.qemu]: [1]
'''),
        '192.168.1.88:5555': LdPlayerAdbParser.parseAndroidGetpropOutput('''
[ro.product.manufacturer]: [Google]
[ro.product.model]: [Pixel 7 Pro]
[ro.hardware]: [vbox86]
'''),
      };

      expect(propsMap['emulator-5554']!.qemuAvdName, isNull);
      expect(propsMap['emulator-5554']!.isThirdPartyEmulator, isTrue);
      expect(propsMap['emulator-5558']!.qemuAvdName, equals('AI_Type'));

      final ldInstances = const [
        LdPlayerInstance(index: 0, name: 'LDPlayer', isRunning: true),
        LdPlayerInstance(index: 1, name: 'LDPlayer-1', isRunning: true),
        LdPlayerInstance(index: 2, name: 'LDPlayer-2', isRunning: false),
      ];

      final catalog = LdPlayerAdbParser.mergeVirtualDeviceCatalog(
        standardAvds: ['AI_Type', 'Pixel_10_Pro_persona_127_0_0_1'],
        ldPlayerInstances: ldInstances,
        adbDevices: adbRecords,
        adbPropsBySerial: propsMap,
      );

      // Ky vong thu tu: 3 LDPlayer (#0, #1, #2) + 1 ADB ngoai (192.168.1.88:5555) + 2 AVD chuan = 6 muc, KHONG trung lap
      expect(
        catalog.map((e) => e.id).toList(),
        equals([
          'ldplayer:0',
          'ldplayer:1',
          'ldplayer:2',
          'adb:192.168.1.88:5555',
          'AI_Type',
          'Pixel_10_Pro_persona_127_0_0_1',
        ]),
      );

      expect(catalog[0].displayLabel, equals('[LDPlayer #0] LDPlayer (Đang chạy - emulator-5554)'));
      expect(catalog[1].displayLabel, equals('[LDPlayer #1] LDPlayer-1 (Đang chạy - emulator-5556)'));
      expect(catalog[2].displayLabel, equals('[LDPlayer #2] LDPlayer-2 (Sẵn sàng)'));
      expect(catalog[3].displayLabel, contains('[LDPlayer / ADB]'));
      expect(catalog[3].displayLabel, contains('192.168.1.88:5555'));
      expect(catalog[4].displayLabel, equals('AI_Type (Đang chạy - emulator-5558)'));
      expect(catalog[5].displayLabel, equals('Pixel_10_Pro_persona_127_0_0_1'));
    });

    test('Gan gia lap LDPlayer va ADB vao Ho so Nhan vat AI va luu ben vung qua F5', () async {
      final userKey = 'ldp_test_${DateTime.now().millisecondsSinceEpoch}';
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

      final p1 = PersonaProfile(
        ip: '127.0.0.1',
        name: 'Nhân vật LDPlayer 0',
        age: 25,
        gender: 'Nam',
        bio: 'Gắn LDPlayer số 0',
        avatarPrompt: 'portrait',
        avdName: 'ldplayer:0',
      );

      final p2 = PersonaProfile(
        ip: '127.0.0.1',
        entryKey: '127.0.0.1##2',
        name: 'Nhân vật LDPlayer 1',
        age: 23,
        gender: 'Nữ',
        bio: 'Gắn LDPlayer số 1 cùng IP localhost',
        avatarPrompt: 'portrait',
        avdName: 'ldplayer:1',
      );

      final p3 = PersonaProfile(
        ip: '10.20.30.55',
        name: 'Nhân vật ADB Studio',
        age: 27,
        gender: 'Nam',
        bio: 'Gắn thiết bị ADB từ Android Studio',
        avatarPrompt: 'portrait',
        avdName: 'adb:emulator-5554',
      );

      expect(await svc.updatePersona(p1), isTrue);
      expect(await svc.updatePersona(p2), isTrue);
      expect(await svc.updatePersona(p3), isTrue);

      svc.clearCache();
      final reloaded = await svc.loadSavedPersonas(forceReload: true);

      expect(reloaded['127.0.0.1']?.avdName, equals('ldplayer:0'));
      expect(reloaded['127.0.0.1##2']?.avdName, equals('ldplayer:1'));
      expect(reloaded['10.20.30.55']?.avdName, equals('adb:emulator-5554'));

      expect(
        await Socks5ProxyService().hasDeviceForPersona(
          ip: '127.0.0.1',
          personaName: p1.name,
          avdName: reloaded['127.0.0.1']?.avdName,
        ),
        isTrue,
      );
      expect(
        await Socks5ProxyService().hasDeviceForPersona(
          ip: '10.20.30.55',
          personaName: p3.name,
          avdName: reloaded['10.20.30.55']?.avdName,
        ),
        isTrue,
      );
    });

    test('mxh-tool CLI helper script sinh ra hop le cu phap Python 3 va ho tro ldplayer/adb', () async {
      final scriptPath = await CliAutomationBridgeService().ensureCliHelperInstalled();
      expect(File(scriptPath).existsSync(), isTrue);
      final content = File(scriptPath).readAsStringSync();
      expect(content.contains('ldplayer:'), isTrue);
      expect(content.contains('adb:'), isTrue);

      final pyCheck = await Process.run('python3', ['-W', 'error', '-m', 'py_compile', scriptPath]);
      expect(pyCheck.exitCode, equals(0), reason: 'Python syntax/warning error: ${pyCheck.stderr}');
    });
  });
}
