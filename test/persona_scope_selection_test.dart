import 'package:flutter_test/flutter_test.dart';
import 'package:agent_mxh_auto/models/persona_profile_model.dart';
import 'package:agent_mxh_auto/core/services/persona_service.dart';
import 'package:agent_mxh_auto/core/services/socks5_proxy_service.dart';

void main() {
  group('Chon Nhan Vat (Profiles) cung chung IP 127.0.0.1', () {
    final personas = [
      PersonaProfile(
        ip: '127.0.0.1',
        entryKey: '127.0.0.1',
        name: 'Nhà văn Lâm Vũ',
        age: 41,
        gender: 'Nam',
        bio: 'Nhân vật tự động cho địa chỉ IP 127.0.0.1',
        avatarPrompt: '',
      ),
      PersonaProfile(
        ip: '127.0.0.1',
        entryKey: '127.0.0.1##2',
        name: 'Trường Tồn',
        age: 54,
        gender: 'Nam',
        bio: 'Một ông chú lắm chuyện',
        avatarPrompt: '',
      ),
      PersonaProfile(
        ip: '127.0.0.1',
        entryKey: '127.0.0.1##3',
        name: 'Vk',
        age: 35,
        gender: 'Nữ',
        bio: 'Một cô nàng dễ thương, vui tính, bướng bỉnh.',
        avatarPrompt: '',
      ),
      PersonaProfile(
        ip: '127.0.0.1',
        entryKey: '127.0.0.1##4',
        name: 'Nguyễn Ên',
        age: 25,
        gender: 'Nam',
        bio: 'Nhóc con thích chơi game và xem phim',
        avatarPrompt: '',
      ),
    ];

    test('Chon 1 nhan vat chi danh dau dung 1 dong va Ap dung tra ve dung 1 nhan vat', () {
      final selectedKeys = <String>{};

      // Click chon "Nhà văn Lâm Vũ"
      selectedKeys.add(personas[0].effectiveEntryKey);
      expect(selectedKeys.length, 1);

      // Chi duy nhat dong dau tien duoc check, 3 dong con lai van false
      expect(selectedKeys.contains(personas[0].effectiveEntryKey), isTrue);
      expect(selectedKeys.contains(personas[1].effectiveEntryKey), isFalse);
      expect(selectedKeys.contains(personas[2].effectiveEntryKey), isFalse);
      expect(selectedKeys.contains(personas[3].effectiveEntryKey), isFalse);

      final applied = personas.where((p) => selectedKeys.contains(p.effectiveEntryKey)).toList();
      expect(applied.length, 1);
      expect(applied.single.name, 'Nhà văn Lâm Vũ');

      // Chon them "Vk" (127.0.0.1##3)
      selectedKeys.add(personas[2].effectiveEntryKey);
      expect(selectedKeys.length, 2);

      final appliedTwo = personas.where((p) => selectedKeys.contains(p.effectiveEntryKey)).toList();
      expect(appliedTwo.map((p) => p.name).toList(), ['Nhà văn Lâm Vũ', 'Vk']);

      // Go bo chip "Nhà văn Lâm Vũ" khong lam mat "Vk"
      appliedTwo.removeWhere((item) => item.effectiveEntryKey == personas[0].effectiveEntryKey);
      expect(appliedTwo.length, 1);
      expect(appliedTwo.single.effectiveEntryKey, '127.0.0.1##3');
    });

    test('PersonaService.activeScopeIps va regex ProfileKey giu nguyen khoa phan biet ip##n', () {
      final service = PersonaService();
      service.setActiveScopeIps(['127.0.0.1##2', '127.0.0.1##3']);

      final restored = personas
          .where((p) => service.activeScopeIps.contains(p.effectiveEntryKey))
          .toList();
      expect(restored.map((p) => p.name).toList(), ['Trường Tồn', 'Vk']);

      final scopeHeader = [
        '=== DANH SÁCH NHÂN VẬT ĐƯỢC CHỈ ĐỊNH (SCOPE PERSONAS) ===',
        for (final p in restored)
          '- ProfileKey: ${p.effectiveEntryKey} | IP: ${p.ip} | Họ tên: ${p.name} | Tuổi: ${p.age} | Giới tính: ${p.gender} | Bio: ${p.bio}',
      ].join('\n');

      final extractedKeys = RegExp(r'ProfileKey:\s*([0-9a-zA-Z\.\:\_\-#]+)')
          .allMatches(scopeHeader)
          .map((m) => m.group(1)!.trim())
          .toList();
      expect(extractedKeys, ['127.0.0.1##2', '127.0.0.1##3']);

      service.clearActiveScope();
    });

    test('Socks5ProxyService giu nguyen trackKey ip##n khi goi qua tham so ip don le tu AI Agent', () {
      final trackKey = Socks5ProxyService.normalizeTrackKey('127.0.0.1##3');
      final cleanIp = Socks5ProxyService.extractCleanIp(trackKey);
      expect(trackKey, '127.0.0.1##3');
      expect(cleanIp, '127.0.0.1');

      final socks5 = Socks5ProxyService();
      expect(socks5.isBrowserRunningForIp('127.0.0.1##3'), isFalse);
      expect(socks5.isDeviceRunningForIp('127.0.0.1##3'), isFalse);
    });
  });
}
