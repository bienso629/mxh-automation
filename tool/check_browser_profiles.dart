// Script kiểm chứng thủ công: đọc profile trình duyệt thật trên máy hiện tại.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:agent_mxh_auto/core/services/browser_profile_service.dart';

Future<void> main() async {
  final svc = BrowserProfileService();

  // Đoạn code mô phỏng y hệt luồng thật trong launchPersonaBrowser:
  // 1. Tìm executable trình duyệt mặc định
  String? exe;
  try {
    final r = Process.runSync('xdg-settings', ['get', 'default-web-browser']);
    if (r.exitCode == 0 && r.stdout.toString().trim().isNotEmpty) {
      final desktopId = r.stdout.toString().trim();
      final r2 = Process.runSync('which', [desktopId.split('.')[0].replaceAll('_', '-')]);
      if (r2.exitCode == 0) exe = r2.stdout.toString().trim();
    }
  } catch (_) {}
  exe ??= '/usr/bin/google-chrome';

  print('Trinh duyet binary: $exe');

  // 2. Lấy danh sách profiles
  final profiles = svc.listSystemProfiles(exe);
  print('Tong so profiles: ${profiles.length}');
  for (final p in profiles) {
    final kind = p.kind == BrowserKind.chromium ? 'chromium' : 'firefox';
    final dflt = p.isDefault ? ' [MAC DINH]' : '';
    final email = p.email != null ? ' <${p.email}>' : '';
    print('  - [$kind] id=${p.id} | ten=${p.name}$email$dflt');
  }

  // 3. Kiểm tra resolve 1 profile theo id
  if (profiles.isNotEmpty) {
    final first = profiles.first;
    final resolved = svc.resolveProfile(exe, first.id);
    print('Resolve "${first.id}" => ${resolved != null ? "THANH CONG (${resolved.name})" : "THAT BAI"}');
  } else {
    print('Khong co profile nao de test resolve');
  }

  print('DONE - khong throw exception la OK');
}
