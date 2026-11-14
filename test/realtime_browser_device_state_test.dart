import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_mxh_auto/core/services/browser_profile_service.dart';
import 'package:agent_mxh_auto/core/services/socks5_proxy_service.dart';

void main() {
  group('Đồng bộ tức thì trạng thái Mở/Đóng Browser và Device', () {
    test('Chuẩn hóa khóa định danh độc lập giữa IP gốc và các nhân vật phụ dùng chung IP', () {
      expect(
        Socks5ProxyService.normalizeTrackKey('127.0.0.1'),
        equals('127.0.0.1'),
      );
      expect(
        Socks5ProxyService.normalizeTrackKey('127.0.0.1', entryKey: '127.0.0.1'),
        equals('127.0.0.1'),
      );
      expect(
        Socks5ProxyService.normalizeTrackKey('127.0.0.1', entryKey: '127.0.0.1##2'),
        equals('127.0.0.1##2'),
      );
      expect(
        Socks5ProxyService.extractCleanIp('127.0.0.1##3'),
        equals('127.0.0.1'),
      );
      expect(
        Socks5ProxyService.extractCleanIp('103.45.67.89'),
        equals('103.45.67.89'),
      );
    });

    test('Socks5Session phản ánh chính xác trạng thái Browser (bao gồm handoff profile hệ thống) và Device (bao gồm đang boot LDPlayer)', () {
      final session = Socks5Session(localPort: 0, ip: '127.0.0.1');
      expect(session.hasActiveBrowserState, isFalse);
      expect(session.hasActiveDeviceState, isFalse);

      // Mở trình duyệt với profile hệ thống chuyển giao sang Chrome gốc
      session.browserLaunchedAt = DateTime.now();
      session.browserDelegatedToExistingInstance = true;
      session.browserProfileId = 'Profile 1';
      expect(session.hasActiveBrowserState, isTrue);

      // Khi đóng cửa sổ của Profile 1
      session.browserLaunchedAt = null;
      session.browserDelegatedToExistingInstance = false;
      session.browserProfileId = null;
      expect(session.hasActiveBrowserState, isFalse);

      // Ngay khi vừa gọi ldconsole launch (cửa sổ LDPlayer bật lên, Android đang boot)
      session.ldPlayerIndex = 0;
      session.adbDeviceSerial = 'emulator-5554';
      session.isDeviceBooting = true;
      expect(session.hasActiveDeviceState, isTrue);

      // Sau khi đóng LDPlayer
      session.ldPlayerIndex = null;
      session.adbDeviceSerial = null;
      session.isDeviceBooting = false;
      expect(session.hasActiveDeviceState, isFalse);
    });

    test('Suy luận chính xác chỉ số LDPlayer từ serial ADB chuẩn của Android Studio', () {
      expect(LdPlayerAdbParser.inferLdPlayerIndexFromSerial('emulator-5554'), equals(0));
      expect(LdPlayerAdbParser.inferLdPlayerIndexFromSerial('127.0.0.1:5555'), equals(0));
      expect(LdPlayerAdbParser.inferLdPlayerIndexFromSerial('emulator-5556'), equals(1));
      expect(LdPlayerAdbParser.inferLdPlayerIndexFromSerial('127.0.0.1:5557'), equals(1));
      expect(LdPlayerAdbParser.inferLdPlayerIndexFromSerial('localhost:5559'), equals(2));

      // Thiết bị thật qua USB hoặc WiFi LAN không được nhầm thành LDPlayer
      expect(LdPlayerAdbParser.inferLdPlayerIndexFromSerial('R58M42ABCDE'), isNull);
      expect(LdPlayerAdbParser.inferLdPlayerIndexFromSerial('192.168.1.88:5555'), isNull);
      expect(LdPlayerAdbParser.inferLdPlayerIndexFromSerial(null), isNull);
    });

    test('Phân giải đúng thư mục Profile trình duyệt hệ thống cho Chromium', () {
      final resolved = BrowserProfileService().resolveSystemProfileDirectory(
        Platform.isWindows
            ? r'C:\Program Files\Google\Chrome\Application\chrome.exe'
            : '/usr/bin/google-chrome',
        'Profile 2',
      );
      expect(resolved, isNotNull);
      expect(resolved!.endsWith('Profile 2'), isTrue);
    });
  });
}
