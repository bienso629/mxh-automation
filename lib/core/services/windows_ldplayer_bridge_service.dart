import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'adb_manager_service.dart';
import 'ldplayer_adb_discovery.dart';

/// Trạng thái tích hợp LDPlayer (driver VT-x & cầu nối ADB) trên Windows
class LdPlayerBridgeStatus {
  final bool isSupported;
  final bool isInstalled;
  final String? installDir;
  final String? dnPlayerPath;
  final String? supInstallPath;
  final String? adbPath;
  final String? driverServiceName;
  final bool isDriverRunning;
  final bool isAehdRunning;
  final int detectedVmCount;
  final List<String> connectedAdbSerials;

  const LdPlayerBridgeStatus({
    required this.isSupported,
    required this.isInstalled,
    this.installDir,
    this.dnPlayerPath,
    this.supInstallPath,
    this.adbPath,
    this.driverServiceName,
    this.isDriverRunning = false,
    this.isAehdRunning = false,
    this.detectedVmCount = 0,
    this.connectedAdbSerials = const [],
  });

  bool get isReady => isInstalled && isDriverRunning && !isAehdRunning;
}

/// Kết quả thực thi tích hợp chuyển sang LDPlayer (kích hoạt VT-x + kết nối ADB)
class LdPlayerBridgeResult {
  final bool success;
  final bool uacCancelled;
  final String message;
  final String? ldPlayerDir;
  final String? dnPlayerPath;
  final String? adbPath;
  final String? driverService;
  final bool driverStarted;
  final List<String> connectedSerials;
  final String? detailLog;

  const LdPlayerBridgeResult({
    required this.success,
    this.uacCancelled = false,
    required this.message,
    this.ldPlayerDir,
    this.dnPlayerPath,
    this.adbPath,
    this.driverService,
    this.driverStarted = false,
    this.connectedSerials = const [],
    this.detailLog,
  });
}

/// Dịch vụ tích hợp LDPlayer vào ứng dụng và Android Studio trên mọi máy Windows.
///
/// Tích hợp trọn vẹn quy trình `CHUYEN_SANG_LDPLAYER.ps1` trực tiếp trong app với
/// cơ chế dò đường dẫn tự động (không gắn cứng đường dẫn user hay ổ đĩa):
/// 1. Dừng tiến trình Android Emulator xung đột (`qemu-system-x86_64`, `emulator`) và dịch vụ `aehd`.
/// 2. Cấu hình & kích hoạt driver ảo hóa VT-x của LDPlayer (`Ld9BoxSup` / `LdBoxSup` / `LdVBoxSup` + `SUPInstall.exe`).
/// 3. Tự động tìm `dnplayer.exe` (LDPlayer) qua Registry, biến môi trường, tất cả ổ đĩa và khởi chạy nếu chưa mở.
/// 4. Tự động tìm `adb.exe` (Android SDK của user hiện tại, ADB nhúng hoặc `adb.exe` đi kèm LDPlayer),
///    kết nối toàn bộ cổng ADB của LDPlayer (`127.0.0.1:5555`, `5557`, ...) và trả kết quả về app.
class WindowsLdPlayerBridgeService {
  static final WindowsLdPlayerBridgeService _instance = WindowsLdPlayerBridgeService._internal();
  factory WindowsLdPlayerBridgeService() => _instance;
  WindowsLdPlayerBridgeService._internal();

  bool get isSupported => Platform.isWindows;

  /// Tìm đường dẫn `dnplayer.exe` trong thư mục cài đặt LDPlayer
  static String? findDnPlayerPath(String? ldInstallDir) {
    if (ldInstallDir == null || ldInstallDir.trim().isEmpty) return null;
    final cleanDir = ldInstallDir.trim();
    for (final exe in ['dnplayer.exe', 'LDPlayer.exe']) {
      final candidate = File(p.join(cleanDir, exe));
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
    return null;
  }

  /// Tự động tìm `SUPInstall.exe` (driver VT-x của LDPlayer) trên mọi máy Windows
  static String? findSupInstallPath({String? ldInstallDir}) {
    final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final programFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';

    final candidates = <String>[
      if (ldInstallDir != null && ldInstallDir.trim().isNotEmpty) ...[
        p.join(ldInstallDir.trim(), 'vbox', 'SUPInstall.exe'),
        p.join(ldInstallDir.trim(), 'SUPInstall.exe'),
        p.join(p.dirname(ldInstallDir.trim()), 'ldplayer9box', 'SUPInstall.exe'),
        p.join(p.dirname(ldInstallDir.trim()), 'ldplayerbox', 'SUPInstall.exe'),
      ],
      p.join(programFiles, 'ldplayer9box', 'SUPInstall.exe'),
      p.join(programFiles, 'ldplayerbox', 'SUPInstall.exe'),
      p.join(programFiles, 'dnplayerext2', 'SUPInstall.exe'),
      p.join(programFilesX86, 'ldplayer9box', 'SUPInstall.exe'),
      p.join(programFilesX86, 'ldplayerbox', 'SUPInstall.exe'),
      p.join(programFilesX86, 'dnplayerext2', 'SUPInstall.exe'),
    ];

    for (final c in candidates) {
      if (c.isNotEmpty && File(c).existsSync()) {
        return c;
      }
    }
    return null;
  }

  /// Tự động tìm đường dẫn `adb.exe` tốt nhất trên máy Windows hiện tại (không gắn cứng username)
  Future<String?> resolveBestAdbPath({String? ldInstallDir}) async {
    final binName = Platform.isWindows ? 'adb.exe' : 'adb';
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';

    final candidates = <String>[];
    for (final envKey in ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
      final sdkDir = Platform.environment[envKey];
      if (sdkDir != null && sdkDir.trim().isNotEmpty) {
        candidates.add(p.join(sdkDir.trim(), 'platform-tools', binName));
      }
    }

    if (Platform.isWindows) {
      if (localAppData.isNotEmpty) {
        candidates.add(p.join(localAppData, 'Android', 'Sdk', 'platform-tools', 'adb.exe'));
      }
      if (home.isNotEmpty) {
        candidates.add(p.join(home, 'AppData', 'Local', 'Android', 'Sdk', 'platform-tools', 'adb.exe'));
      }
      for (final drive in ['C', 'D', 'E', 'F']) {
        candidates.add('$drive:\\Android\\Sdk\\platform-tools\\adb.exe');
      }
    }

    for (final c in candidates) {
      if (c.isNotEmpty && File(c).existsSync()) {
        return c;
      }
    }

    // Ưu tiên tiếp theo: ADB nhúng của chính ứng dụng
    try {
      final embedded = await AdbManagerService().getEmbeddedAdbPath();
      if (File(embedded).existsSync()) {
        return embedded;
      }
    } catch (_) {}

    // Fallback: adb.exe đi kèm trong thư mục cài đặt LDPlayer (chạy được ngay cả khi không cài Android Studio)
    final resolvedLdDir = ldInstallDir ?? (await LdPlayerService().findInstallation())?.installDir;
    if (resolvedLdDir != null && resolvedLdDir.isNotEmpty) {
      final ldAdb = File(p.join(resolvedLdDir, binName));
      if (ldAdb.existsSync()) {
        return ldAdb.path;
      }
    }

    return null;
  }

  /// Tạo nội dung script PowerShell tự động nhận diện đường dẫn động cho mọi máy Windows
  static String buildIntegrationScript({
    required String resultJsonPath,
    String? detectedLdDir,
    String? detectedDnPlayerPath,
    String? detectedSupInstallPath,
    String? detectedAdbPath,
    List<int> targetVmIndices = const [0],
    bool launchDefaultVm = true,
  }) {
    String psQuote(String? value) {
      if (value == null || value.trim().isEmpty) return "''";
      return "'${value.trim().replaceAll("'", "''")}'";
    }

    final indicesList = targetVmIndices.isEmpty ? [0] : targetVmIndices.toSet().toList()..sort();
    final indicesPs = '@(${indicesList.join(', ')})';
    final launchFlag = launchDefaultVm ? r'$true' : r'$false';

    return '''
\$ErrorActionPreference = 'Continue'
\$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

\$resultPath = ${psQuote(resultJsonPath)}
\$ldDir = ${psQuote(detectedLdDir)}
\$dnPlayerPath = ${psQuote(detectedDnPlayerPath)}
\$supInstallPath = ${psQuote(detectedSupInstallPath)}
\$adbPath = ${psQuote(detectedAdbPath)}
\$targetIndices = $indicesPs
\$launchDefaultVm = $launchFlag
\$logs = New-Object System.Collections.Generic.List[string]

function Add-Log([string]\$msg) {
  \$logs.Add(\$msg) | Out-Null
}

# 1. Tự động tìm thư mục cài đặt LDPlayer nếu chưa được truyền vào
if (-not \$ldDir -or -not (Test-Path \$ldDir)) {
  foreach (\$envKey in @('LDPLAYER_HOME', 'LDPLAYER_DIR')) {
    \$envVal = [Environment]::GetEnvironmentVariable(\$envKey)
    if (\$envVal -and (Test-Path \$envVal)) {
      \$ldDir = \$envVal.ToString().Trim().TrimEnd('\\')
      break
    }
  }
}

if (-not \$ldDir -or -not (Test-Path \$ldDir)) {
  \$regPaths = @(
    'HKCU:\\Software\\XuanZhi\\LDPlayer9',
    'HKCU:\\Software\\XuanZhi\\LDPlayer64',
    'HKCU:\\Software\\XuanZhi\\LDPlayer',
    'HKCU:\\Software\\leidian\\ldplayer9',
    'HKLM:\\SOFTWARE\\XuanZhi\\LDPlayer9',
    'HKLM:\\SOFTWARE\\WOW6432Node\\XuanZhi\\LDPlayer9',
    'HKLM:\\SOFTWARE\\XuanZhi\\LDPlayer64',
    'HKLM:\\SOFTWARE\\WOW6432Node\\XuanZhi\\LDPlayer64',
    'HKLM:\\SOFTWARE\\XuanZhi\\LDPlayer',
    'HKLM:\\SOFTWARE\\WOW6432Node\\XuanZhi\\LDPlayer'
  )
  foreach (\$rp in \$regPaths) {
    if (Test-Path \$rp) {
      try {
        \$props = Get-ItemProperty -Path \$rp -ErrorAction SilentlyContinue
        if (\$props.InstallDir -and (Test-Path \$props.InstallDir)) {
          \$ldDir = \$props.InstallDir.ToString().Trim().TrimEnd('\\')
          break
        }
      } catch {}
    }
  }
}

if (-not \$ldDir -or -not (Test-Path \$ldDir)) {
  \$uninstallRoots = @(
    'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
    'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
    'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'
  )
  foreach (\$uRoot in \$uninstallRoots) {
    try {
      \$uninstallMatches = Get-ItemProperty -Path \$uRoot -ErrorAction SilentlyContinue | Where-Object { \$_.DisplayName -match 'LDPlayer' }
      foreach (\$m in \$uninstallMatches) {
        if (\$m.InstallLocation -and (Test-Path \$m.InstallLocation)) {
          \$ldDir = \$m.InstallLocation.ToString().Trim().TrimEnd('\\')
          break
        }
        if (\$m.DisplayIcon) {
          \$iconFile = (\$m.DisplayIcon.ToString().Split(',')[0]).Trim('"').Trim()
          if (\$iconFile -and (Test-Path \$iconFile)) {
            \$ldDir = (Split-Path -Parent \$iconFile).TrimEnd('\\')
            break
          }
        }
      }
      if (\$ldDir -and (Test-Path \$ldDir)) { break }
    } catch {}
  }
}

if (-not \$ldDir -or -not (Test-Path \$ldDir)) {
  if (\$env:LOCALAPPDATA) {
    foreach (\$localSub in @('LDPlayer\\LDPlayer9', 'LDPlayer\\LDPlayer64', 'LDPlayer9')) {
      \$candLocal = Join-Path \$env:LOCALAPPDATA \$localSub
      if ((Test-Path (Join-Path \$candLocal 'dnplayer.exe')) -or (Test-Path (Join-Path \$candLocal 'ldconsole.exe'))) {
        \$ldDir = \$candLocal
        break
      }
    }
  }
}

if (-not \$ldDir -or -not (Test-Path \$ldDir)) {
  \$subFolders = @(
    'LDPlayer\\LDPlayer9',
    'LDPlayer\\LDPlayer64',
    'LDPlayer\\LDPlayer5',
    'LDPlayer\\LDPlayer4.0',
    'LDPlayer\\LDPlayer3.0',
    'LDPlayer9',
    'XuanZhi\\LDPlayer9',
    'XuanZhi\\LDPlayer',
    'ChangZhi\\dnplayer2',
    'leidian\\LDPlayer9',
    'Program Files\\LDPlayer\\LDPlayer9',
    'Program Files (x86)\\LDPlayer\\LDPlayer9'
  )
  \$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { \$_.Root -match '^[A-Z]:\\\\\$' } | Select-Object -ExpandProperty Root
  :outerLoop foreach (\$drv in \$drives) {
    foreach (\$sub in \$subFolders) {
      \$cand = Join-Path \$drv \$sub
      if ((Test-Path (Join-Path \$cand 'dnplayer.exe')) -or (Test-Path (Join-Path \$cand 'ldconsole.exe')) -or (Test-Path (Join-Path \$cand 'dnconsole.exe'))) {
        \$ldDir = \$cand
        break outerLoop
      }
    }
  }
}

if (\$ldDir -and (-not \$dnPlayerPath -or -not (Test-Path \$dnPlayerPath))) {
  foreach (\$exe in @('dnplayer.exe', 'LDPlayer.exe')) {
    \$candExe = Join-Path \$ldDir \$exe
    if (Test-Path \$candExe) {
      \$dnPlayerPath = \$candExe
      break
    }
  }
}

# 2. Tự động tìm SUPInstall.exe trên mọi ổ đĩa / ProgramFiles
if (-not \$supInstallPath -or -not (Test-Path \$supInstallPath)) {
  \$supCandidates = @(
    (Join-Path \$env:ProgramFiles 'ldplayer9box\\SUPInstall.exe'),
    (Join-Path \$env:ProgramFiles 'ldplayerbox\\SUPInstall.exe'),
    (Join-Path \$env:ProgramFiles 'dnplayerext2\\SUPInstall.exe')
  )
  if (\${env:ProgramFiles(x86)}) {
    \$supCandidates += (Join-Path \${env:ProgramFiles(x86)} 'ldplayer9box\\SUPInstall.exe')
    \$supCandidates += (Join-Path \${env:ProgramFiles(x86)} 'ldplayerbox\\SUPInstall.exe')
    \$supCandidates += (Join-Path \${env:ProgramFiles(x86)} 'dnplayerext2\\SUPInstall.exe')
  }
  if (\$ldDir) {
    \$supCandidates += (Join-Path \$ldDir 'vbox\\SUPInstall.exe')
    \$supCandidates += (Join-Path \$ldDir 'SUPInstall.exe')
  }
  foreach (\$sc in \$supCandidates) {
    if (\$sc -and (Test-Path \$sc)) {
      \$supInstallPath = \$sc
      break
    }
  }
}

# 3. Tự động tìm adb.exe động theo user hiện tại (Android Studio SDK -> LDPlayer -> PATH)
if (-not \$adbPath -or -not (Test-Path \$adbPath)) {
  \$adbCandidates = @()
  if (\$env:ANDROID_HOME) { \$adbCandidates += (Join-Path \$env:ANDROID_HOME 'platform-tools\\adb.exe') }
  if (\$env:ANDROID_SDK_ROOT) { \$adbCandidates += (Join-Path \$env:ANDROID_SDK_ROOT 'platform-tools\\adb.exe') }
  if (\$env:LOCALAPPDATA) { \$adbCandidates += (Join-Path \$env:LOCALAPPDATA 'Android\\Sdk\\platform-tools\\adb.exe') }
  if (\$env:USERPROFILE) { \$adbCandidates += (Join-Path \$env:USERPROFILE 'AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe') }
  \$adbCandidates += 'C:\\Android\\Sdk\\platform-tools\\adb.exe'
  \$adbCandidates += 'D:\\Android\\Sdk\\platform-tools\\adb.exe'
  \$adbCandidates += 'E:\\Android\\Sdk\\platform-tools\\adb.exe'
  if (\$ldDir) { \$adbCandidates += (Join-Path \$ldDir 'adb.exe') }

  foreach (\$ac in \$adbCandidates) {
    if (\$ac -and (Test-Path \$ac)) {
      \$adbPath = \$ac
      break
    }
  }
  if (-not \$adbPath) {
    \$adbCmd = Get-Command adb.exe -ErrorAction SilentlyContinue
    if (\$adbCmd) { \$adbPath = \$adbCmd.Source }
  }
}

# 4. Dừng Android Studio AVD / AEHD đang chiếm quyền VT-x
Add-Log 'Dừng tiến trình Android Emulator xung đột (qemu-system-x86_64, emulator)...'
Stop-Process -Name 'qemu-system-x86_64','emulator','emulator-headless' -Force -ErrorAction SilentlyContinue

\$aehdSvc = Get-Service -Name 'aehd' -ErrorAction SilentlyContinue
if (\$aehdSvc) {
  Add-Log 'Dừng dịch vụ AEHD và chuyển về khởi động thủ công (demand)...'
  & sc.exe stop aehd 2>&1 | Out-Null
  & sc.exe config aehd start= demand 2>&1 | Out-Null
}

# 5. Bật driver VT-x của LDPlayer (Ld9BoxSup / LdBoxSup / LdVBoxSup)
if (\$supInstallPath -and (Test-Path \$supInstallPath)) {
  Add-Log "Cài đặt / sửa chữa driver qua SUPInstall: \$supInstallPath"
  try {
    Start-Process -FilePath \$supInstallPath -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
  } catch {}
}

\$driverService = ''
foreach (\$drvName in @('Ld9BoxSup', 'LdBoxSup', 'LdVBoxSup')) {
  \$qOut = & sc.exe query \$drvName 2>&1
  if (\$LASTEXITCODE -eq 0) {
    \$driverService = \$drvName
    break
  }
}

\$driverStarted = \$false
if (\$driverService) {
  Add-Log "Cấu hình và khởi động driver \$driverService..."
  & sc.exe config \$driverService start= system 2>&1 | Out-Null
  & sc.exe start \$driverService 2>&1 | Out-Null
  Start-Sleep -Milliseconds 500
  \$stateOut = (& sc.exe query \$driverService 2>&1 | Out-String)
  if (\$stateOut -match 'RUNNING') {
    \$driverStarted = \$true
    Add-Log "Driver \$driverService đang hoạt động (RUNNING)."
  } else {
    Add-Log "Driver \$driverService chưa báo RUNNING: \$(\$stateOut.Trim())"
  }
} else {
  Add-Log 'Không tìm thấy dịch vụ driver Ld9BoxSup/LdBoxSup trên hệ thống.'
}

# 6. Bật cờ ADB trên các giả lập LDPlayer và mở giả lập mặc định nếu cần
\$ldConsole = ''
if (\$ldDir) {
  foreach (\$cbin in @('ldconsole.exe', 'dnconsole.exe')) {
    \$cp = Join-Path \$ldDir \$cbin
    if (Test-Path \$cp) { \$ldConsole = \$cp; break }
  }
}

\$hasRunningVm = \$false
\$runningIndices = New-Object System.Collections.Generic.List[int]
if (\$ldConsole) {
  try {
    \$listOut = & \$ldConsole list2 2>&1
    foreach (\$line in \$listOut) {
      \$cols = \$line.ToString().Split(',')
      if (\$cols.Length -ge 5) {
        \$idxVal = 0
        if ([int]::TryParse(\$cols[0].Trim(), [ref]\$idxVal)) {
          if (\$cols[4].Trim() -eq '1') {
            \$hasRunningVm = \$true
            if (-not \$runningIndices.Contains(\$idxVal)) { \$runningIndices.Add(\$idxVal) | Out-Null }
          }
        }
      }
    }
  } catch {}
}

if (\$launchDefaultVm -and -not \$hasRunningVm) {
  if (\$ldConsole) {
    \$firstIdx = \$targetIndices[0]
    & \$ldConsole modify --index \$firstIdx --adb 1 2>&1 | Out-Null
  }
  if (\$dnPlayerPath -and (Test-Path \$dnPlayerPath)) {
    \$firstIdx = \$targetIndices[0]
    Add-Log "Khởi chạy LDPlayer (index=\$firstIdx): \$dnPlayerPath"
    Start-Process -FilePath \$dnPlayerPath -ArgumentList "index=\$firstIdx" -WorkingDirectory \$ldDir
    if (-not \$runningIndices.Contains(\$firstIdx)) { \$runningIndices.Add(\$firstIdx) | Out-Null }
  } elseif (\$ldConsole) {
    \$firstIdx = \$targetIndices[0]
    Add-Log "Khởi chạy LDPlayer qua ldconsole (index=\$firstIdx)"
    & \$ldConsole launch --index \$firstIdx 2>&1 | Out-Null
    if (-not \$runningIndices.Contains(\$firstIdx)) { \$runningIndices.Add(\$firstIdx) | Out-Null }
  }
}

foreach (\$ti in \$targetIndices) {
  if (-not \$runningIndices.Contains(\$ti)) { \$runningIndices.Add(\$ti) | Out-Null }
}

# 7. Kết nối ADB tới tất cả các cổng LDPlayer (5555 + index * 2) với cơ chế chờ thông minh
\$connectedSerials = New-Object System.Collections.Generic.List[string]
if (\$adbPath -and (Test-Path \$adbPath)) {
  Add-Log "Đang kết nối ADB bằng: \$adbPath"
  \$maxAttempts = if (\$launchDefaultVm -and -not \$hasRunningVm) { 10 } else { 3 }
  for (\$attempt = 1; \$attempt -le \$maxAttempts; \$attempt++) {
    foreach (\$rIdx in \$runningIndices) {
      \$port = 5555 + (\$rIdx * 2)
      & \$adbPath connect "127.0.0.1:\$port" 2>&1 | Out-Null
    }
    \$devLines = & \$adbPath devices 2>&1
    \$connectedSerials.Clear()
    foreach (\$dl in \$devLines) {
      \$sLine = \$dl.ToString().Trim()
      if (\$sLine -match '^(\\S+)\\s+device\$') {
        \$serial = \$Matches[1]
        if (-not \$connectedSerials.Contains(\$serial)) {
          \$connectedSerials.Add(\$serial) | Out-Null
        }
      }
    }
    if (\$connectedSerials.Count -gt 0) {
      break
    }
    if (\$attempt -lt \$maxAttempts) {
      Start-Sleep -Seconds 2
    }
  }
  Add-Log ("Thiết bị ADB đang online: " + (\$connectedSerials -join ', '))
} else {
  Add-Log 'Không tìm thấy adb.exe trên hệ thống.'
}

\$ok = (\$ldDir -ne '') -and (\$driverStarted -or \$connectedSerials.Count -gt 0 -or (\$dnPlayerPath -ne ''))
\$payload = @{
  success = \$ok
  ld_dir = \$ldDir
  dnplayer_path = \$dnPlayerPath
  sup_install_path = \$supInstallPath
  adb_path = \$adbPath
  driver_service = \$driverService
  driver_started = \$driverStarted
  connected_serials = @(\$connectedSerials)
  logs = @(\$logs)
}
\$payload | ConvertTo-Json -Depth 4 | Out-File -Encoding utf8 -FilePath \$resultPath
''';
  }

  /// Phân tích JSON kết quả trả về từ script PowerShell
  static LdPlayerBridgeResult parseResultJson(String rawJson) {
    try {
      // Loại bỏ UTF-8 BOM nếu PowerShell Out-File -Encoding utf8 thêm vào đầu file
      final clean = rawJson.startsWith('\uFEFF') ? rawJson.substring(1).trim() : rawJson.trim();
      final decoded = jsonDecode(clean);
      if (decoded is! Map<String, dynamic>) {
        return const LdPlayerBridgeResult(
          success: false,
          message: 'Không đọc được kết quả cấu hình LDPlayer.',
        );
      }

      final success = decoded['success'] == true;
      final ldDir = decoded['ld_dir']?.toString().trim();
      final dnPath = decoded['dnplayer_path']?.toString().trim();
      final adbPath = decoded['adb_path']?.toString().trim();
      final driverSvc = decoded['driver_service']?.toString().trim();
      final driverStarted = decoded['driver_started'] == true;

      final serialsRaw = decoded['connected_serials'];
      final serials = <String>[];
      if (serialsRaw is List) {
        for (final item in serialsRaw) {
          final s = item?.toString().trim() ?? '';
          if (s.isNotEmpty) serials.add(s);
        }
      } else if (serialsRaw is String && serialsRaw.trim().isNotEmpty) {
        serials.add(serialsRaw.trim());
      }

      final logsRaw = decoded['logs'];
      final logLines = <String>[];
      if (logsRaw is List) {
        for (final item in logsRaw) {
          final s = item?.toString().trim() ?? '';
          if (s.isNotEmpty) logLines.add(s);
        }
      } else if (logsRaw is String && logsRaw.trim().isNotEmpty) {
        logLines.add(logsRaw.trim());
      }

      String msg;
      if (ldDir == null || ldDir.isEmpty) {
        msg = 'Không tìm thấy thư mục cài đặt LDPlayer trên máy tính này. Hãy cài đặt LDPlayer hoặc đặt biến môi trường LDPLAYER_HOME.';
      } else if (serials.isNotEmpty) {
        msg = 'Đã bật driver VT-x LDPlayer và kết nối thành công ${serials.length} thiết bị ADB (${serials.join(', ')}).';
      } else if (driverStarted) {
        msg = 'Đã bật driver VT-x LDPlayer ($driverSvc) và khởi chạy giả lập. Đợi vài giây để LDPlayer khởi động xong rồi bấm Quét lại.';
      } else if (success) {
        msg = 'Đã gửi lệnh kích hoạt LDPlayer tại $ldDir.';
      } else {
        msg = 'Không thể khởi động driver VT-x của LDPlayer. Hãy kiểm tra tính năng tắt Hyper-V/WHPX và khởi động lại máy nếu cần.';
      }

      return LdPlayerBridgeResult(
        success: success,
        message: msg,
        ldPlayerDir: (ldDir != null && ldDir.isNotEmpty) ? ldDir : null,
        dnPlayerPath: (dnPath != null && dnPath.isNotEmpty) ? dnPath : null,
        adbPath: (adbPath != null && adbPath.isNotEmpty) ? adbPath : null,
        driverService: (driverSvc != null && driverSvc.isNotEmpty) ? driverSvc : null,
        driverStarted: driverStarted,
        connectedSerials: serials,
        detailLog: logLines.join('\n'),
      );
    } catch (e) {
      return LdPlayerBridgeResult(
        success: false,
        message: 'Lỗi đọc kết quả kích hoạt LDPlayer: $e',
      );
    }
  }

  /// Kiểm tra trạng thái tích hợp LDPlayer hiện tại (không cần UAC Administrator)
  Future<LdPlayerBridgeStatus> getIntegrationStatus({bool forceRefresh = false}) async {
    if (!isSupported) {
      return const LdPlayerBridgeStatus(isSupported: false, isInstalled: false);
    }

    final install = await LdPlayerService().findInstallation(forceRefresh: forceRefresh);
    final instances = install != null
        ? await LdPlayerService().discoverInstances(forceRefresh: forceRefresh)
        : const <LdPlayerInstance>[];
    final dnPlayer = findDnPlayerPath(install?.installDir);
    final supInstall = findSupInstallPath(ldInstallDir: install?.installDir);
    final adbPath = await resolveBestAdbPath(ldInstallDir: install?.installDir);

    String? driverName;
    bool driverRunning = false;
    bool aehdRunning = false;

    try {
      final res = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"$aehd = ((sc.exe query aehd 2>&1 | Out-String) -match 'RUNNING'); "
              r"$drv = ''; $drvRun = $false; "
              r"foreach ($n in @('Ld9BoxSup','LdBoxSup','LdVBoxSup')) { "
              r"  $o = (sc.exe query $n 2>&1 | Out-String); "
              r"  if ($LASTEXITCODE -eq 0) { $drv = $n; $drvRun = ($o -match 'RUNNING'); break } "
              r"}; "
              r'Write-Output "$drv|$drvRun|$aehd"',
        ],
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 4));

      final out = utf8.decode(res.stdout is List<int> ? res.stdout as List<int> : const [], allowMalformed: true).trim();
      final parts = out.split('|');
      if (parts.length == 3) {
        if (parts[0].trim().isNotEmpty) driverName = parts[0].trim();
        driverRunning = parts[1].trim().toLowerCase() == 'true';
        aehdRunning = parts[2].trim().toLowerCase() == 'true';
      }
    } catch (_) {}

    final connectedSerials = <String>[];
    if (adbPath != null && adbPath.isNotEmpty) {
      try {
        final devRes = await Process.run(
          adbPath,
          ['devices', '-l'],
          stdoutEncoding: null,
          stderrEncoding: null,
        ).timeout(const Duration(seconds: 3));
        if (devRes.exitCode == 0) {
          final out = utf8.decode(
            devRes.stdout is List<int> ? devRes.stdout as List<int> : const [],
            allowMalformed: true,
          );
          final records = LdPlayerAdbParser.parseAdbDevicesLongOutput(out);
          for (final rec in records) {
            if (rec.state == 'device') connectedSerials.add(rec.serial);
          }
        }
      } catch (_) {}
    }

    return LdPlayerBridgeStatus(
      isSupported: true,
      isInstalled: install != null,
      installDir: install?.installDir,
      dnPlayerPath: dnPlayer,
      supInstallPath: supInstall,
      adbPath: adbPath,
      driverServiceName: driverName,
      isDriverRunning: driverRunning,
      isAehdRunning: aehdRunning,
      detectedVmCount: instances.length,
      connectedAdbSerials: connectedSerials,
    );
  }

  /// Chạy quy trình chuyển sang LDPlayer với quyền Administrator (UAC):
  /// dừng AVD/AEHD -> bật driver Ld9BoxSup + SUPInstall -> khởi chạy LDPlayer -> kết nối ADB.
  Future<LdPlayerBridgeResult> activateLdPlayerIntegration({
    bool launchDefaultVm = true,
  }) async {
    if (!isSupported) {
      return const LdPlayerBridgeResult(
        success: false,
        message: 'Tính năng kích hoạt driver LDPlayer chỉ hỗ trợ trên hệ điều hành Windows.',
      );
    }

    final install = await LdPlayerService().findInstallation(forceRefresh: true);
    final instances = install != null
        ? await LdPlayerService().discoverInstances(forceRefresh: true)
        : const <LdPlayerInstance>[];
    final targetIndices = <int>[
      0,
      ...instances.where((vm) => vm.isRunning).map((vm) => vm.index),
    ];

    final dnPlayerPath = findDnPlayerPath(install?.installDir);
    final supInstallPath = findSupInstallPath(ldInstallDir: install?.installDir);
    final adbPath = await resolveBestAdbPath(ldInstallDir: install?.installDir);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final tempDir = Directory.systemTemp.path;
    final scriptFile = File(p.join(tempDir, 'agent_mxh_ldplayer_bridge_$stamp.ps1'));
    final resultFile = File(p.join(tempDir, 'agent_mxh_ldplayer_bridge_$stamp.json'));

    final scriptContent = buildIntegrationScript(
      resultJsonPath: resultFile.path,
      detectedLdDir: install?.installDir,
      detectedDnPlayerPath: dnPlayerPath,
      detectedSupInstallPath: supInstallPath,
      detectedAdbPath: adbPath,
      targetVmIndices: targetIndices,
      launchDefaultVm: launchDefaultVm,
    );

    try {
      // Ghi file kèm UTF-8 BOM để Windows PowerShell 5.1 đọc chuẩn tiếng Việt
      scriptFile.writeAsBytesSync([0xEF, 0xBB, 0xBF, ...utf8.encode(scriptContent)]);
      final escapedScriptPath = scriptFile.path.replaceAll("'", "''");
      final launcher = "Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden "
          "-ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File \"' + '$escapedScriptPath' + '\"')";

      final res = await Process.run('powershell', ['-NoProfile', '-Command', launcher]);
      debugPrint('[LDPlayerBridge] launcher exit=${res.exitCode} stderr=${res.stderr}');

      if (!resultFile.existsSync()) {
        return const LdPlayerBridgeResult(
          success: false,
          uacCancelled: true,
          message: 'Bạn đã từ chối hộp thoại cấp quyền Administrator (UAC) nên chưa thể bật driver VT-x cho LDPlayer.',
        );
      }

      final rawJson = resultFile.readAsStringSync();
      return parseResultJson(rawJson);
    } catch (e) {
      return LdPlayerBridgeResult(
        success: false,
        message: 'Lỗi khi kích hoạt tích hợp LDPlayer: $e',
      );
    } finally {
      try {
        if (scriptFile.existsSync()) scriptFile.deleteSync();
      } catch (_) {}
      try {
        if (resultFile.existsSync()) resultFile.deleteSync();
      } catch (_) {}
    }
  }

  /// Kết nối lại nhanh ADB tới tất cả máy ảo LDPlayer đang chạy (không cần hỏi UAC)
  Future<List<String>> quickReconnectAdbOnly() async {
    if (!isSupported) return const [];
    final install = await LdPlayerService().findInstallation(forceRefresh: true);
    final adbPath = await resolveBestAdbPath(ldInstallDir: install?.installDir);
    if (adbPath == null || adbPath.isEmpty) return const [];

    final instances = install != null
        ? await LdPlayerService().discoverInstances(forceRefresh: true)
        : const <LdPlayerInstance>[];
    final indices = <int>{0, ...instances.where((i) => i.isRunning).map((i) => i.index)};

    for (final idx in indices) {
      final tcp = LdPlayerAdbParser.ldPlayerTcpSerial(idx);
      try {
        await Process.run(
          adbPath,
          ['connect', tcp],
          stdoutEncoding: null,
          stderrEncoding: null,
        ).timeout(const Duration(seconds: 2));
      } catch (_) {}
    }

    try {
      final devRes = await Process.run(
        adbPath,
        ['devices', '-l'],
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 3));
      if (devRes.exitCode == 0) {
        final out = utf8.decode(
          devRes.stdout is List<int> ? devRes.stdout as List<int> : const [],
          allowMalformed: true,
        );
        return LdPlayerAdbParser.parseAdbDevicesLongOutput(out)
            .where((r) => r.state == 'device')
            .map((r) => r.serial)
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}
