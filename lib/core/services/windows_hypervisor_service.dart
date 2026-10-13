import 'dart:io';
import 'package:flutter/foundation.dart';

/// Trạng thái tăng tốc phần cứng cho Android Emulator trên Windows.
enum HypervisorState { enabled, disabled, pendingRestart, unknown }

/// Quản lý bật/tắt Hyper-V và Windows Hypervisor Platform (WHPX) trên Windows
/// để Android Emulator chạy tăng tốc phần cứng, người dùng không phải gõ lệnh.
class WindowsHypervisorService {
  static final WindowsHypervisorService _instance = WindowsHypervisorService._internal();
  factory WindowsHypervisorService() => _instance;
  WindowsHypervisorService._internal();

  static const List<String> _features = ['HypervisorPlatform', 'Microsoft-Hyper-V-All'];

  bool get isSupported => Platform.isWindows;

  /// Kiểm tra trạng thái WHPX (không cần quyền Administrator).
  /// Win32_OptionalFeature.InstallState: 1 = Enabled, 2 = Disabled, 3 = Absent.
  Future<HypervisorState> getState() async {
    if (!isSupported) return HypervisorState.unknown;
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "(Get-CimInstance -ClassName Win32_OptionalFeature -Filter \"Name='HypervisorPlatform'\").InstallState",
      ]);
      final out = res.stdout.toString().trim();
      if (out == '1') return HypervisorState.enabled;
      if (out == '2' || out == '3') return HypervisorState.disabled;
      return HypervisorState.unknown;
    } catch (e) {
      debugPrint('[Hypervisor] Lỗi kiểm tra trạng thái: $e');
      return HypervisorState.unknown;
    }
  }

  /// Bật hoặc tắt Hyper-V + WHPX. Windows sẽ hiện hộp thoại UAC xin quyền Administrator.
  /// Trả về true nếu lệnh DISM chạy thành công (cần khởi động lại máy để áp dụng).
  Future<bool> setEnabled(bool enable) async {
    if (!isSupported) return false;
    final action = enable ? '/Enable-Feature /All' : '/Disable-Feature';
    final dismCmds = _features
        .map((f) => 'dism.exe /Online $action /FeatureName:$f /NoRestart /Quiet')
        .join('; ');
    // Mã 0 = thành công, 3010 = thành công nhưng cần khởi động lại.
    final inner = '$dismCmds; exit \$LASTEXITCODE';
    final script = "\$p = Start-Process powershell -Verb RunAs -Wait -PassThru -WindowStyle Hidden "
        "-ArgumentList '-NoProfile','-Command','${inner.replaceAll("'", "''")}'; exit \$p.ExitCode";
    try {
      final res = await Process.run('powershell', ['-NoProfile', '-Command', script]);
      debugPrint('[Hypervisor] exit=${res.exitCode} stderr=${res.stderr}');
      return res.exitCode == 0 || res.exitCode == 3010;
    } catch (e) {
      debugPrint('[Hypervisor] Lỗi bật/tắt: $e');
      return false;
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
