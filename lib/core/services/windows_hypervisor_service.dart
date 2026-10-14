import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Trạng thái tăng tốc phần cứng cho Android Emulator trên Windows.
enum HypervisorState { enabled, disabled, pendingRestart, unknown }

/// Quản lý bật/tắt tăng tốc máy ảo (Windows Hypervisor Platform - WHPX) trên Windows
/// để Android Emulator chạy tăng tốc phần cứng, người dùng không phải gõ lệnh.
///
/// Lưu ý: chỉ gỡ feature bằng DISM là CHƯA đủ để tắt hypervisor, vì các tính năng khác
/// (WSL2, Docker, Windows Sandbox, Memory Integrity/VBS) vẫn khởi động hypervisor lúc boot.
/// Vì vậy phải kết hợp thêm `bcdedit /set hypervisorlaunchtype off|auto`.
class WindowsHypervisorService {
  static final WindowsHypervisorService _instance = WindowsHypervisorService._internal();
  factory WindowsHypervisorService() => _instance;
  WindowsHypervisorService._internal();

  bool get isSupported => Platform.isWindows;

  /// Kiểm tra trạng thái thực tế (không cần quyền Administrator):
  /// - `HypervisorPresent`: hypervisor có đang thật sự chạy hay không.
  /// - `InstallState` của feature HypervisorPlatform: 1 = Enabled, 2 = Disabled, 3 = Absent.
  /// Chỉ coi là "bật" khi cả hai đều đúng (emulator cần cả hai để dùng WHPX).
  Future<HypervisorState> getState() async {
    if (!isSupported) return HypervisorState.unknown;
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "\$hp = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent; "
            "\$fs = (Get-CimInstance -ClassName Win32_OptionalFeature -Filter \"Name='HypervisorPlatform'\").InstallState; "
            "Write-Output \"\$hp|\$fs\"",
      ]);
      final out = res.stdout.toString().trim();
      debugPrint('[Hypervisor] Trạng thái: $out');
      final parts = out.split('|');
      if (parts.length != 2) return HypervisorState.unknown;
      final running = parts[0].trim().toLowerCase() == 'true';
      final featureOn = parts[1].trim() == '1';
      return (running && featureOn) ? HypervisorState.enabled : HypervisorState.disabled;
    } catch (e) {
      debugPrint('[Hypervisor] Lỗi kiểm tra trạng thái: $e');
      return HypervisorState.unknown;
    }
  }

  /// Bật hoặc tắt tăng tốc máy ảo. Windows sẽ hiện hộp thoại UAC xin quyền Administrator.
  /// Trả về true nếu thao tác thành công (cần khởi động lại máy để áp dụng).
  Future<bool> setEnabled(bool enable) async {
    if (!isSupported) return false;

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final tempDir = Directory.systemTemp.path;
    final scriptFile = File(p.join(tempDir, 'agent_mxh_hyperv_$stamp.ps1'));
    final resultFile = File(p.join(tempDir, 'agent_mxh_hyperv_$stamp.txt'));

    // Ghi script ra file .ps1 để tránh lỗi escape chuỗi khi truyền qua Start-Process -Verb RunAs.
    // Kết quả từng bước được ghi ra file txt để đọc lại chính xác (không phụ thuộc ExitCode).
    final resultPath = resultFile.path.replaceAll("'", "''");
    final script = enable
        ? '''
\$ErrorActionPreference = 'Continue'
dism.exe /Online /Enable-Feature /All /FeatureName:HypervisorPlatform /NoRestart /Quiet | Out-Null
\$feat = \$LASTEXITCODE
bcdedit.exe /set hypervisorlaunchtype auto | Out-Null
\$bcd = \$LASTEXITCODE
"\$feat|\$bcd" | Out-File -Encoding ascii -FilePath '$resultPath'
'''
        : '''
\$ErrorActionPreference = 'Continue'
# Chặn hypervisor khởi động lúc boot (kể cả khi WSL2 / Docker / Sandbox / VBS còn bật)
bcdedit.exe /set hypervisorlaunchtype off | Out-Null
\$bcd = \$LASTEXITCODE
dism.exe /Online /Disable-Feature /FeatureName:HypervisorPlatform /NoRestart /Quiet | Out-Null
\$feat = \$LASTEXITCODE
"\$feat|\$bcd" | Out-File -Encoding ascii -FilePath '$resultPath'
''';

    try {
      scriptFile.writeAsStringSync(script);
      final scriptPath = scriptFile.path.replaceAll("'", "''");
      final launcher = "Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden "
          "-ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File \"' + '$scriptPath' + '\"')";
      final res = await Process.run('powershell', ['-NoProfile', '-Command', launcher]);
      debugPrint('[Hypervisor] launcher exit=${res.exitCode} stderr=${res.stderr}');

      // Không có file kết quả => người dùng bấm "No" ở hộp thoại UAC
      if (!resultFile.existsSync()) return false;
      final parts = resultFile.readAsStringSync().trim().split('|');
      debugPrint('[Hypervisor] Kết quả (feature|bcdedit): $parts');
      if (parts.length != 2) return false;

      // DISM: 0 = OK, 3010 = OK cần restart. Khi tắt: feature vốn chưa bật cũng chấp nhận.
      const okFeat = {'0', '3010'};
      final feat = parts[0].trim();
      final bcd = parts[1].trim();
      final featOk = okFeat.contains(feat) || (!enable && feat != '');
      return featOk && bcd == '0';
    } catch (e) {
      debugPrint('[Hypervisor] Lỗi bật/tắt: $e');
      return false;
    } finally {
      try {
        if (scriptFile.existsSync()) scriptFile.deleteSync();
      } catch (_) {}
      try {
        if (resultFile.existsSync()) resultFile.deleteSync();
      } catch (_) {}
    }
  }

  /// Khởi động lại máy sau 5 giây.
  Future<void> restartNow() async {
    if (!isSupported) return;
    try {
      await Process.run('shutdown', ['/r', '/t', '5']);
    } catch (_) {}
  }
}
