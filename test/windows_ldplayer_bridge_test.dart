import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_mxh_auto/core/services/windows_ldplayer_bridge_service.dart';

void main() {
  group('WindowsLdPlayerBridgeService - Tu dong tich hop LDPlayer tren moi may Windows', () {
    test('buildIntegrationScript dung path dong (Registry, LOCALAPPDATA, moi o dia), khong gan cung ten user', () {
      final script = WindowsLdPlayerBridgeService.buildIntegrationScript(
        resultJsonPath: r'C:\Temp\result.json',
        targetVmIndices: const [0, 1],
        launchDefaultVm: true,
      );

      expect(script.contains('Wing386'), isFalse);
      expect(script.contains(r'HKCU:\Software\XuanZhi\LDPlayer9'), isTrue);
      expect(script.contains('Get-PSDrive -PSProvider FileSystem'), isTrue);
      expect(script.contains(r'$env:LOCALAPPDATA'), isTrue);
      expect(script.contains(r'$env:ProgramFiles'), isTrue);
      expect(script.contains('sc.exe stop aehd'), isTrue);
      expect(script.contains('Ld9BoxSup'), isTrue);
      expect(script.contains('SUPInstall.exe'), isTrue);
      expect(script.contains('dnplayer.exe'), isTrue);
      expect(script.contains('127.0.0.1:\$port'), isTrue);
      expect(script.contains('@(0, 1)'), isTrue);
    });

    test('parseResultJson xu ly chuan ket qua co BOM UTF-8, serial ADB va truong hop chua cai LDPlayer', () {
      const okJsonWithBom = '\uFEFF{'
          '"success": true,'
          '"ld_dir": "D:\\\\LDPlayer\\\\LDPlayer9",'
          '"dnplayer_path": "D:\\\\LDPlayer\\\\LDPlayer9\\\\dnplayer.exe",'
          '"adb_path": "C:\\\\Users\\\\AnyUser\\\\AppData\\\\Local\\\\Android\\\\Sdk\\\\platform-tools\\\\adb.exe",'
          '"driver_service": "Ld9BoxSup",'
          '"driver_started": true,'
          '"connected_serials": ["127.0.0.1:5555", "emulator-5554"],'
          '"logs": ["Driver Ld9BoxSup dang hoat dong"]'
          '}';

      final parsedOk = WindowsLdPlayerBridgeService.parseResultJson(okJsonWithBom);
      expect(parsedOk.success, isTrue);
      expect(parsedOk.ldPlayerDir, r'D:\LDPlayer\LDPlayer9');
      expect(parsedOk.driverService, 'Ld9BoxSup');
      expect(parsedOk.driverStarted, isTrue);
      expect(parsedOk.connectedSerials, ['127.0.0.1:5555', 'emulator-5554']);
      expect(parsedOk.message.contains('2 thiết bị ADB'), isTrue);

      const missingLdJson = '{"success": false, "ld_dir": "", "driver_started": false, "connected_serials": []}';
      final parsedMissing = WindowsLdPlayerBridgeService.parseResultJson(missingLdJson);
      expect(parsedMissing.success, isFalse);
      expect(parsedMissing.ldPlayerDir, isNull);
      expect(parsedMissing.message.contains('Không tìm thấy thư mục cài đặt LDPlayer'), isTrue);
    });

    test('File docs/DUNG_LDPLAYER_CHO_ANDROID_STUDIO.bat va docs/CHUYEN_SANG_LDPLAYER.ps1 khong gan cung duong dan user', () {
      final batFile = File('docs/DUNG_LDPLAYER_CHO_ANDROID_STUDIO.bat');
      final ps1File = File('docs/CHUYEN_SANG_LDPLAYER.ps1');
      if (!batFile.existsSync() || !ps1File.existsSync()) {
        // Thư mục docs/ nằm trong .gitignore nên chỉ kiểm tra khi tồn tại cục bộ
        return;
      }

      final batText = batFile.readAsStringSync();
      final ps1Text = ps1File.readAsStringSync();
      expect(batText.contains('Wing386'), isFalse);
      expect(batText.contains(r'%~dp0CHUYEN_SANG_LDPLAYER.ps1'), isTrue);
      expect(ps1Text.contains('Wing386'), isFalse);
      expect(ps1Text.contains(r'$PSCommandPath'), isTrue);
      expect(ps1Text.contains(r'$env:LOCALAPPDATA'), isTrue);
      expect(ps1Text.contains(r'Get-PSDrive -PSProvider FileSystem'), isTrue);
    });
  });
}
